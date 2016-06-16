require "logger"

module Sidekiq
  # #
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   def perform(a : Int64, b : Int64, c : Float64)
  #     # do some work
  #   end
  # end
  #
  # Note that you **must** annotate your perform method arguments so
  # so that Sidekiq knows how to marshal your jobs at compile-time.
  # Only JSON::Type parameters are allowed, e.g. Int64 is allowed but Int32 is not.
  #
  # To create a new job, you do this:
  #
  #   HardWorker.async.perform(1_i64, 2_i64, 3_f64)
  #
  module Worker
    property jid : String = ""
    property bid : String?
    property! logger : ::Logger

    def logger
      @logger = ::Logger.new(STDOUT) unless @logger
      @logger.not_nil!
    end

    macro included
      extend Sidekiq::Worker::ClassMethods
      Sidekiq::Job.register("{{@type}}", ->{ {{@type}}.new.as(Sidekiq::Worker) })

      macro method_added(a_def)
        \{% if a_def.name.id == "perform".id %}
          \{% if a_def.args.size > 0 %}
            # We define a tuple with types from each of the arguments.
            # For example, if the args are `name : String, age : Int32`
            # we generate `tuple = Tuple(String, Int32)`.
            ARGS_TUPLE = Tuple(\{{
                                  a_def.args.map do |arg|
                                    if arg.restriction
                                      arg.restriction
                                    else
                                      raise "argument '#{arg}' must have a type restriction"
                                    end
                                  end.join(", ").id
                                  }})
          \{% end %}

          def _perform(data : String)
            \{% if a_def.args.size > 0 %}
              # Then we parse the JSON to this tuple
              tuple = ARGS_TUPLE.from_json(data)
              # And splat it into `perform`
              perform(*tuple)
            \{% else %}
              perform()
            \{% end %}
          end

          class PerformProxy < Sidekiq::Job
            \{% args_list = a_def.args.join(", ").id %}
            \{% args = a_def.args.map { |a| a.name }.join(", ").id %}

            def perform(\{{args_list}})
              data = ""
              \{% if a_def.args.size > 0 %}
                data = ARGS_TUPLE.new(\{{args}}).to_json
              \{% end %}
              _perform(data)
            end
            def perform_at(interval : Time, \{{args_list}})
              data = ""
              \{% if a_def.args.size > 0 %}
                data = ARGS_TUPLE.new(\{{args}}).to_json
              \{% end %}
              _perform_at(interval, data)
            end
            def perform_in(interval : Time::Span, \{{args_list}})
              data = ""
              \{% if a_def.args.size > 0 %}
                data = ARGS_TUPLE.new(\{{args}}).to_json
              \{% end %}
              _perform_in(interval, data)
            end
          end
        \{% end %}
      end
    end

    module ClassMethods
      # no block
      def async(queue = "default")
        {% begin %}
        job = {{@type.id}}::PerformProxy.new
        job.klass = self.name
        job.queue = queue
        job
        {% end %}
      end

      # if passed a block, yields the job
      def async(queue = "default")
        {% begin %}
        job = {{@type.id}}::PerformProxy.new
        job.klass = self.name
        job.queue = queue
        yield job
        job
        {% end %}
      end
    end
  end
end
