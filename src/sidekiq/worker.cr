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
  # Note that perform_async is a class method, perform is an instance method.
  module Worker
    property jid
    property? bid

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
