require "./util"
require "./fetch"

module Sidekiq
  ##
  # The Processor is a standalone fiber which:
  #
  # 1. fetches a job from Redis
  # 2. executes the job
  #   a. instantiate the Worker
  #   b. run the middleware chain
  #   c. call #perform
  #
  # A Processor can exit due to shutdown (processor_stopped)
  # or due to an error during job execution (processor_died)
  #
  # If an error occurs in the job execution, the
  # Processor calls the Manager to create a new one
  # to replace itself and exits.
  #
  class Processor
    include Util

    getter job : Sidekiq::UnitOfWork?
    getter identity : String

    def initialize(mgr : Sidekiq::Server)
      @identity = ""
      @mgr = mgr
      @done = false
      @down = nil
      @job = nil
    end

    def logger
      @mgr.logger
    end

    def terminate
      @done = true
    end

    def start
      safe_routine(@mgr, "processor") do
        @identity = Fiber.current.object_id.to_s(36)
        run
      end
    end

    def run
      begin
        while !@done
          process_one
        end
        @mgr.processor_stopped(self)
      #rescue Sidekiq::Shutdown
        #@mgr.processor_stopped(self)
      rescue ex : Exception
        @mgr.processor_died(self, ex)
      end
    end

    def process_one
      @job = x = fetch
      process(x) if x
      @job = nil
    end

    def get_one
      begin
        work = @mgr.fetcher.retrieve_work
        (logger.info { "Redis is online, #{Time.now - @down.not_nil!} sec downtime" }; @down = nil) if @down
        work
      rescue ex
        handle_fetch_exception(ex)
      end
    end

    def fetch
      j = get_one
      if j && @done
        j.requeue
        nil
      else
        j
      end
    end

    def handle_fetch_exception(ex)
      if !@down
        @down = Time.now
        logger.error("Error fetching job: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      sleep(1)
      nil
    end

    def process(work)
      jobstr = work.job
      ack = false
      begin
        hash = JSON.parse(jobstr)
        job = Sidekiq::Job.new
        job.load(hash.as_h)

        stats(job, jobstr) do
          @mgr.middleware.invoke(job, @mgr) do
            # Only ack if we either attempted to start this job or
            # successfully completed it. This prevents us from
            # losing jobs if a middleware raises an exception before yielding
            ack = true
            job.execute
          end
        end
        ack = true
      #rescue Sidekiq::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
        #ack = false
      rescue ex : Exception
        handle_exception(@mgr, ex, { "job" => jobstr })
        raise ex
      ensure
        work.acknowledge if ack
      end
    end

    @@WORKER_STATE = Hash(String, Hash(String, String)).new
    @@PROCESSED = 0
    @@FAILURE = 0

    def stats(job, str)
      @@WORKER_STATE[@identity] = {"queue" => job.queue, "payload" => str, "run_at" => Time.now.epoch.to_s }

      begin
        yield
      rescue ex : Exception
        @@FAILURE += 1
        raise ex
      ensure
        @@WORKER_STATE.delete(@identity)
        @@PROCESSED += 1
      end
    end

  end
end
