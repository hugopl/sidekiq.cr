require "sidekiq/util"
require "sidekiq/fetch"

class Sidekiq
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

    getter job : Sidekiq::BasicFetch::UnitOfWork

    def initialize(mgr)
      @mgr = mgr
      @down = false
      @done = false
      @job = nil
    end

    def logger
      @mgr.logger
    end

    def terminate
      @done = true
    end

    def start
      @thread ||= safe_routine("processor", &method(:run))
    end

    def run
      begin
        while !@done
          process_one
        end
        @mgr.processor_stopped(self)
      rescue Sidekiq::Shutdown
        @mgr.processor_stopped(self)
      rescue ex : Exception
        @mgr.processor_died(self, ex)
      end
    end

    def process_one
      @job = fetch
      process(@job) if @job
      @job = nil
    end

    def get_one
      begin
        work = @strategy.retrieve_work
        (logger.info { "Redis is online, #{Time.now - @down} sec downtime" }; @down = nil) if @down
        work
      rescue Sidekiq::Shutdown
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
      queue = work.queue_name

      ack = false
      begin
        job = JSON.parse(jobstr)
        klass  = job["class"].constantize
        worker = klass.new
        worker.jid = job["jid"]

        stats(worker, job, queue) do
          @mgr.server_middleware.invoke(worker, job, queue) do
            # Only ack if we either attempted to start this job or
            # successfully completed it. This prevents us from
            # losing jobs if a middleware raises an exception before yielding
            ack = true
            worker.perform(*(job["args"].clone))
          end
        end
        ack = true
      rescue Sidekiq::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
        ack = false
      rescue ex : Exception
        handle_exception(ex, job || { :job => jobstr })
        raise
      ensure
        work.acknowledge if ack
      end
    end

    def thread_identity
      @str ||= Fiber.current.object_id.to_s(36)
    end

    @@WORKER_STATE = Hash(String, Hash(String, String)).new
    @@PROCESSED = 0
    @@FAILURE = 0

    def stats(worker, job, queue)
      tid = thread_identity
      @@WORKER_STATE[tid] = {"queue" => queue, "payload" => job, "run_at" => Time.now.to_i.to_s }

      begin
        yield
      rescue Exception
        @@FAILURE += 1
        raise
      ensure
        @@WORKER_STATE.delete(tid)
        @@PROCESSED += 1
      end
    end

  end
end
