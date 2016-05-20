class Sidekiq
  class BasicFetch
    # We want the fetch operation to timeout every few seconds so we
    # can check if the process is shutting down.
    TIMEOUT = 2

    UnitOfWork = Struct.new(:queue, :job, :pool) do
      def acknowledge
        # nothing to do
      end

      def queue_name
        queue.sub(/.*queue:/, "")
      end

      def requeue
        pool.redis do |conn|
          conn.rpush("queue:#{queue_name}", job)
        end
      end
    end

    getter pool
    getter queues
    getter logger

    def initialize(@logger, @pool, queues)
      @queues = queues.map { |q| "queue:#{q}" }
      @strictly_ordered_queues = false
    end

    def strict!
      @strictly_ordered_queues = true
      @queues = @queues.uniq
      @queues << TIMEOUT
    end

    def retrieve_work
      name, job = @pool.redis { |conn| conn.brpop(*queues_cmd) }
      UnitOfWork.new(name, job, pool) if work
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
        queues = @queues.shuffle.uniq
        queues << TIMEOUT
        queues
      end
    end

    def bulk_requeue(inprogress : Array(UnitOfWork))
      return if inprogress.empty?

      logger.debug { "Re-queueing terminated jobs" }
      jobs_to_requeue = {} of String => Array(String)
      inprogress.each do |unit_of_work|
        jobs_to_requeue[unit_of_work.queue_name] ||= [] of String
        jobs_to_requeue[unit_of_work.queue_name] << unit_of_work.job
      end

      pool.redis do |conn|
        conn.pipelined do
          jobs_to_requeue.each do |queue, jobs|
            conn.rpush("queue:#{queue}", jobs)
          end
        end
      end
      logger.info("Pushed #{inprogress.size} jobs back to Redis")
    rescue ex
      logger.warn("Failed to requeue #{inprogress.size} jobs: #{ex.message}")
    end

  end
end
