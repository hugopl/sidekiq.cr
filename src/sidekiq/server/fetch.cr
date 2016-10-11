module Sidekiq
  abstract class UnitOfWork
    abstract def job : String
    abstract def acknowledge : Bool
    abstract def requeue : Bool
  end

  abstract class Fetch
    abstract def retrieve_work(ctx : Sidekiq::Context) : UnitOfWork
    abstract def bulk_requeue(ctx : Sidekiq::Context, jobs : Array(UnitOfWork)) : Int32
  end

  class BasicFetch < ::Sidekiq::Fetch
    # We want the fetch operation to timeout every few seconds so we
    # can check if the process is shutting down.
    TIMEOUT = 2

    class UnitOfWork < ::Sidekiq::UnitOfWork
      def initialize(@queue : String, @job : String, @ctx : Sidekiq::Context)
      end

      def job
        @job
      end

      def acknowledge
        # nothing to do
      end

      def queue_name
        @queue.sub(/.*queue:/, "")
      end

      def requeue
        @ctx.pool.redis do |conn|
          conn.rpush("queue:#{queue_name}", @job)
        end
      end
    end

    getter queues : Array(String)

    def initialize(queues)
      @queues = queues.map { |q| "queue:#{q}" }
      @strictly_ordered_queues = false
    end

    def strict!
      @strictly_ordered_queues = true
      @queues = @queues.uniq
    end

    def retrieve_work(ctx)
      arr = ctx.pool.redis { |conn| conn.brpop(@queues, TIMEOUT) }.as(Array(Redis::RedisValue))
      if arr.size == 2
        UnitOfWork.new(arr[0].to_s, arr[1].to_s, ctx)
      end
    end

    # Creating the Redis#brpop command takes into account any
    # configured queue weights. By default Redis#brpop returns
    # data from the first queue that has pending elements. We
    # recreate the queue command each time we invoke Redis#brpop
    # to honor weights and avoid queue starvation.
    def queues_cmd
      if @strictly_ordered_queues
        @queues
      else
        @queues.shuffle.uniq
      end
    end

    def bulk_requeue(ctx, inprogress : Array(Sidekiq::UnitOfWork))
      return 0 if inprogress.empty?

      jobs_to_requeue = {} of String => Array(String)
      inprogress.each do |unit_of_work|
        jobs_to_requeue[unit_of_work.queue_name] ||= [] of String
        jobs_to_requeue[unit_of_work.queue_name] << unit_of_work.job
      end

      count = 0
      ctx.pool.redis do |conn|
        conn.pipelined do |pipeline|
          jobs_to_requeue.each do |queue, jobs|
            jobs.each do |job|
              # Crystal-Redis sends array as one value, we are unable to do rpush("queue", jobs)
              pipeline.rpush("queue:#{queue}", job)
            end
            count += jobs.size
          end
        end
      end
      count
    end
  end
end
