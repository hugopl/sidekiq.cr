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
          def _perform(args : Array(JSON::Type))
            perform(
              \{% for arg, index in a_def.args %}
                \{% if arg.restriction %}
                  args[\{{index}}].as(\{{arg.restriction}}),
                \{% else %}
                  \{{ raise "argument '#{arg}' must have a type restriction" }}
                \{% end %}
              \{% end %}
            )
          end

          class SidekiqJobProxy < Sidekiq::Job
            \{% args_list = a_def.args.join(", ").id %}
            \{% args = a_def.args.map { |a| a.name }.join(", ").id %}

            def perform(\{{args_list}})
              _perform(\{{args}})
            end
            def perform_bulk(\{{args_list}})
              _perform_bulk(\{{args}})
            end
            def perform_bulk(args : Array(Array(JSON::Type)))
              _perform_bulk(args)
            end
            def perform_at(interval : Time, \{{args_list}})
              _perform_at(interval, \{{args}})
            end
            def perform_in(interval : Time::Span, \{{args_list}})
              _perform_in(interval, \{{args}})
            end
          end
        \{% end %}
      end
    end

    module ClassMethods
      # no block
      def async(queue = "default")
        {% begin %}
        job = {{@type.id}}::SidekiqJobProxy.new
        job.klass = self.name
        job.queue = queue
        job
        {% end %}
      end

      # if passed a block, yields the job
      def async(queue = "default")
        {% begin %}
        job = {{@type.id}}::SidekiqJobProxy.new
        job.klass = self.name
        job.queue = queue
        yield job
        job
        {% end %}
      end
    end
  end
end
