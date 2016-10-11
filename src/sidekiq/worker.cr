require "logger"

module Sidekiq
  # #
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   def perform(a : Int64, b : Int32, c : Float64)
  #     # do some work
  #   end
  # end
  #
  # Note that you **must** annotate your perform method arguments so
  # so that Sidekiq knows how to marshal your jobs at compile-time.
  #
  # To create a new job, you do this:
  #
  #   HardWorker.async.perform(1_i64, 2, 3_f64)
  #
  # You can set default job options per-Worker with `sidekiq_options`:
  #
  #   class HardWorker
  #     include Sidekiq::Worker
  #     sidekiq_options do |job|
  #       job.queue = "critical"
  #       job.retry = 5
  #     end
  #
  # You can dynamically customize job options by passing a block to +async+, like so:
  #
  #   HardWorker.async do |job|
  #     # job is a Sidekiq::Job
  #     job.queue = "foo"
  #     job.retry = false
  #   end.perform(1_i64, 2, 3_f64)
  #
  module Worker
    OPTION_BLOCKS = Hash(String, Proc(Sidekiq::Job, Nil)).new

    property! jid : String
    property bid : String?
    property! logger : ::Logger

    def logger
      @logger ||= Sidekiq::Client.default_context.logger
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
            \{% res = a_def.args.map { |a| a.restriction }.join(", ").id %}
            \{% json = (a_def.args.size > 0) ? "ARGS_TUPLE.new(#{args}).to_json".id : "[]" %}

            def perform(\{{args_list}})
              _perform(\{{json}})
            end
            \{% if a_def.args.size > 0 %}
              def perform_bulk(argses : Array({\{{res}}}))
                _perform_bulk(argses.map {|(\{{args}})| \{{json}} })
              end
            \{% end %}
            def perform_at(interval : Time, \{{args_list}})
              _perform_at(interval, \{{json}})
            end
            def perform_in(interval : Time::Span, \{{args_list}})
              _perform_in(interval, \{{json}})
            end
          end
        \{% end %}
      end
    end

    module ClassMethods
      # no block
      def async
        {% begin %}
        job = {{@type.id}}::PerformProxy.new
        job.klass = self.name
        Sidekiq::Worker::OPTION_BLOCKS["{{@type.id}}"]?.try &.call(job)
        job
        {% end %}
      end

      # if passed a block, yields the job
      def async
        {% begin %}
        job = {{@type.id}}::PerformProxy.new
        job.klass = self.name
        Sidekiq::Worker::OPTION_BLOCKS["{{@type.id}}"]?.try &.call(job)
        yield job
        job
        {% end %}
      end

      def sidekiq_options(&block : Sidekiq::Job -> Nil)
        captured = block
        {% begin %}
        if Sidekiq::Worker::OPTION_BLOCKS["{{@type.id}}"]?
          raise ArgumentError.new("Already defined sidekiq_options for {{@type.id}}")
        end
        Sidekiq::Worker::OPTION_BLOCKS["{{@type.id}}"] = captured
        {% end %}
      end
    end
  end
end
