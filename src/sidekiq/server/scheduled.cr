require "./util"

module Sidekiq
  module Scheduled
    SETS = %w(retry schedule)

    class Enq
      def enqueue_jobs(ctx, now=Time.now, sorted_sets=SETS)
        # A job's "score" in Redis is the time at which it should be processed.
        # Just check Redis for the set of jobs with a timestamp before now.
        nowstr = "%.6f" % now.epoch_f
        ctx.pool.redis do |conn|
          sorted_sets.each do |sorted_set|
            # Get the next item in the queue if it's score (time to execute) is <= now.
            # We need to go through the list one at a time to reduce the risk of something
            # going wrong between the time jobs are popped from the scheduled queue and when
            # they are pushed onto a work queue and losing the jobs.
            while jobstr = conn.zrangebyscore(sorted_set, "-inf", nowstr, limit: [0, 1]).first do

              # Pop item off the queue and add it to the work queue. If the job can't be popped from
              # the queue, it's because another process already popped it so we can move on to the
              # next one.
              if conn.zrem(sorted_set, jobstr)
                hash = JSON.parse(jobstr)
                job = Sidekiq::Job.new
                job.load(hash.as_h)
                # A lot of work just to update the enqueued_at attribute :-(
                Sidekiq::Client.push(job)
              end
            end
          end
        end
      end
    end

    ##
    # The Poller checks Redis every N seconds for jobs in the retry or scheduled
    # set have passed their timestamp and should be enqueued.  If so, it
    # just pops the job back onto its original queue so the
    # workers can pick it up like any other job.
    class Poller
      include Util

      INITIAL_WAIT = 10

      def initialize(ctx)
        @ctx = ctx
        @enq = Sidekiq::Scheduled::Enq.new
        @done = false
      end

      def terminate
        @done = true
      end

      def start
        safe_coroutine("scheduler") do
          initial_wait

          while !@done
            enqueue
            wait
          end
          @ctx.logger.info("Scheduler exiting...")
        end
      end

      def enqueue
        begin
          @enq.enqueue_jobs(@ctx)
        rescue ex
          # Most likely a problem with redis networking.
          # Punt and try again at the next interval
          @ctx.logger.error ex.message
          ex.backtrace.each do |bt|
            @ctx.logger.error(bt)
          end
        end
      end

      private def wait
        @sleeper.pop(random_poll_interval)
      rescue Timeout::Error
        # expected
      rescue ex
        # if poll_interval_average hasn't been calculated yet, we can
        # raise an error trying to reach Redis.
        @ctx.logger.error ex.message
        @ctx.logger.error ex.backtrace.first
        sleep 5
      end

      # Calculates a random interval that is ±50% the desired average.
      def random_poll_interval
        poll_interval_average * rand + poll_interval_average.to_f / 2
      end

      # We do our best to tune the poll interval to the size of the active Sidekiq
      # cluster.  If you have 30 processes and poll every 15 seconds, that means one
      # Sidekiq is checking Redis every 0.5 seconds - way too often for most people
      # and really bad if the retry or scheduled sets are large.
      #
      # Instead try to avoid polling more than once every 15 seconds.  If you have
      # 30 Sidekiq processes, we'll poll every 30 * 15 or 450 seconds.
      # To keep things statistically random, we'll sleep a random amount between
      # 225 and 675 seconds for each poll or 450 seconds on average.  Otherwise restarting
      # all your Sidekiq processes at the same time will lead to them all polling at
      # the same time: the thundering herd problem.
      #
      # We only do this if poll_interval_average is unset (the default).
      def poll_interval_average
        scaled_poll_interval
      end

      # Calculates an average poll interval based on the number of known Sidekiq processes.
      # This minimizes a single point of failure by dispersing check-ins but without taxing
      # Redis if you run many Sidekiq processes.
      def scaled_poll_interval
        pcount = Sidekiq::ProcessSet.new.size
        pcount = 1 if pcount == 0
        pcount * 15
      end

      def initial_wait
        # Have all processes sleep between 5-15 seconds.  10 seconds
        # to give time for the heartbeat to register (if the poll interval is going to be calculated by the number
        # of workers), and 5 random seconds to ensure they don't all hit Redis at the same time.
        total = 0
        total += INITIAL_WAIT
        total += (5 * rand)

        sleep total
      rescue Timeout::Error
      end

    end
  end
end
