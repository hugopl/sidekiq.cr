require "./util"
require "./fetch"

module Sidekiq
  # #
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

    getter work : Sidekiq::UnitOfWork?
    getter identity : String

    def initialize(@mgr : Sidekiq::Server)
      @identity = ""
      @done = false
      @down = nil
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

    private def run
      until @mgr.stopping?
        process_one
      end
      @mgr.processor_stopped(self)
    rescue ex : Exception
      @mgr.processor_died(self, ex)
    end

    def process_one
      @work = work = fetch
      process(work) if work
    end

    def job : Job?
      work = @work
      Job.from_json(work.job) if work
    end

    private def get_one
      work = @mgr.fetcher.retrieve_work(@mgr)
      if @down
        @mgr.logger.info { "Redis is online, #{Time.local - @down.not_nil!} sec downtime" }
        @down = nil
      end
      work
    rescue ex
      handle_fetch_exception(ex)
    end

    private def fetch
      work = get_one
      if work && @done
        work.requeue
        nil
      else
        work
      end
    end

    private def handle_fetch_exception(ex)
      if !@down
        @down = Time.local
        @mgr.logger.error(exception: ex) { "Error fetching job: #{ex}" }
      end
      sleep(1)
    end

    private def process(work)
      jobstr = work.job
      ack = false
      job = Sidekiq::Job.from_json(jobstr)

      stats(job) do
        @mgr.server_middleware.invoke(job, Sidekiq::Client.default_context.not_nil!) do
          # Only ack if we either attempted to start this job or
          # successfully completed it. This prevents us from
          # losing jobs if a middleware raises an exception before yielding
          ack = true
          job.execute(@mgr)
          true
        end
      end
      ack = true
      # rescue Sidekiq::Shutdown
      # Had to force kill this job because it didn't finish
      # within the timeout.  Don't acknowledge the work since
      # we didn't properly finish it.
      # ack = false


    rescue ex : Exception
      handle_exception(@mgr, ex, {"job" => JSON::Any.new(jobstr)})
      raise ex
    ensure
      work.acknowledge if ack
    end

    @@worker_state = Hash(String, Hash(String, (String | Int64 | Sidekiq::Job))).new
    @@processed = 0
    @@failure = 0

    def self.worker_state
      @@worker_state
    end

    def self.fetch_counts
      p, f = @@processed, @@failure
      @@processed = @@failure = 0
      {p, f}
    end

    def self.reset_counts(p, f)
      @@processed += p
      @@failure += f
    end

    def stats(job)
      @@worker_state[@identity] = {"queue" => job.queue, "payload" => job, "run_at" => Time.local.to_unix}

      yield
    rescue ex : Exception
      @@failure += 1
      raise ex
    ensure
      @@worker_state.delete(@identity)
      @@processed += 1
    end
  end
end
