require "logger"

module Sidekiq
  # #
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   perform_types(Int64, Int64, Float64)
  #   def perform(a, b, c)
  #     # do some work
  #   end
  # end
  #
  # Note that you must annotate your perform method with the
  # `perform_types` macro so that Sidekiq knows how to marshal
  # your jobs at compile-time.  Only JSON::Type parameters are allowed!
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
    end

    macro perform_types(*types)
      def _perform(args : Array(JSON::Type))
        {% if types.size == 0 %}
          perform
        {% else %}
          tup = {
          {% for type, index in types %}
            args[{{index}}].as({{type}}),
          {% end %}
          }
          perform(*tup)
        {% end %}
      end
    end

    module ClassMethods
      # no block
      def async(queue = "default")
        job = Sidekiq::Job.new
        job.klass = self.name
        job.queue = queue
        job
      end

      # if passed a block, yields the job
      def async(queue = "default")
        job = Sidekiq::Job.new
        job.klass = self.name
        job.queue = queue
        yield job
        job
      end
    end
  end
end
