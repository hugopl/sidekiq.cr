class Sidekiq

  ##
  # Include this module in your worker class and you can easily create
  # asynchronous jobs:
  #
  # class HardWorker
  #   include Sidekiq::Worker
  #
  #   def perform(*args)
  #     # do some work
  #   end
  # end
  #
  # Then in your app, you can do this:
  #
  #   HardWorker.async.perform(1, 2, 3)
  #
  module Worker
    property jid : String?
    property bid : String?

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
