require "./util"

module Sidekiq
  module Scheduled
    SETS = %w(retry schedule)

    class Enq
      def enqueue_jobs(ctx, now = Time.now, sorted_sets = SETS)
        # A job's "score" in Redis is the time at which it should be processed.
        # Just check Redis for the set of jobs with a timestamp before now.
        count = 0
        nowstr = "%.6f" % now.epoch_f
        ctx.pool.redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get the next item in the queue if it's score (time to execute) is <= now.
            # We need to go through the list one at a time to reduce the risk of something
            # going wrong between the time jobs are popped from the scheduled queue and when
            # they are pushed onto a work queue and losing the jobs.
            loop do
              results = conn.zrangebyscore(sorted_set, "-inf", nowstr, limit: [0, 1]).as(Array)
              break if results.empty?
              jobstr = results[0].as(String)
              job = Sidekiq::Job.from_json(jobstr)

              # Pop item off the queue and add it to the work queue. If the job can't be popped from
              # the queue, it's because another process already popped it so we can move on to the
              # next one.
              if conn.zrem(sorted_set, jobstr)
                # A lot of work just to update the enqueued_at attribute :-(
                job.client.push(job)
                count += 1
              end
            end
          end
          nil
        end
        count
      end
    end

    # #
    # The Poller checks Redis every N seconds for jobs in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the job back onto its original queue so the
    # workers can pick it up like any other job.
    class Poller
      include Util

      INITIAL_WAIT = 10

      def initialize
        @enq = Sidekiq::Scheduled::Enq.new
        @done = false
      end

      def terminate
        @done = true
      end

      def context : Sidekiq::Context
        @ctx.not_nil!
      end

      def start(ctx)
        safe_routine(ctx, "scheduler") do
          initial_wait

          while !@done
            enqueue(ctx)
            wait
          end
          ctx.logger.info("Scheduler exiting...")
        end
      end

      def enqueue(ctx : Sidekiq::Context)
        @ctx = ctx
        begin
          @enq.enqueue_jobs(context)
        rescue ex
          handle_exception(context, ex)
        end
      end

      private def wait
        sleep(random_poll_interval)
      end

      # Calculates a random interval that is ±50% the desired average.
      private def random_poll_interval
        (15 * rand) + (15.to_f / 2)
      end

      private def initial_wait
        # Have all processes sleep between 5-15 seconds.  10 seconds
        # to give time for the heartbeat to register (if the poll interval is going to be calculated by the number
        # of workers), and 5 random seconds to ensure they don't all hit Redis at the same time.
        total = 0
        total += INITIAL_WAIT
        total += (5 * rand)

        sleep total
      end
    end
  end
end
