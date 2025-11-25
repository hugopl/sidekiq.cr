require "../metrics"

module Sidekiq
  module Metrics
    module Query
      # Record job execution metrics to Redis
      # - job_class: The worker class name (e.g., "HardWorker")
      # - duration_ms: Execution time in milliseconds
      # - success: Whether the job completed without raising an exception
      # - timestamp: Unix timestamp truncated to minute (defaults to current time)
      def self.record(job_class : String, duration_ms : Float64, success : Bool, timestamp : Int64 = Metrics.minute_timestamp)
        key = Metrics.key_for(job_class, timestamp)

        Sidekiq.redis do |conn|
          conn.pipelined do |pipe|
            if success
              # Increment success count
              pipe.hincrby(key, "s", 1)
              # Add execution time (only for successful jobs)
              pipe.hincrbyfloat(key, "ms", duration_ms)
              # Increment histogram bucket
              bucket = Histogram.bucket_for(duration_ms)
              pipe.hincrby(key, Histogram.bucket_field(bucket), 1)
            else
              # Only increment failure count for failed jobs
              pipe.hincrby(key, "f", 1)
            end

            # Set TTL on the key (72 hours)
            pipe.expire(key, DEFAULT_RETENTION)

            # Track this job class
            pipe.sadd(CLASSES_KEY, job_class)
          end
        end
      end

      # Get all job classes that have metrics data
      def self.job_classes : Array(String)
        Sidekiq.redis do |conn|
          result = conn.smembers(CLASSES_KEY)
          result.map(&.to_s)
        end
      end

      # Fetch metrics for a specific job class within a time range
      # Returns a hash of timestamp => metrics data
      def self.fetch(job_class : String, start_time : Time, end_time : Time) : Hash(Int64, Hash(String, String))
        result = Hash(Int64, Hash(String, String)).new

        # Generate all minute timestamps in the range
        timestamps = generate_timestamps(start_time, end_time)
        return result if timestamps.empty?

        # Build keys for all timestamps
        keys = timestamps.map { |ts| Metrics.key_for(job_class, ts) }

        # Fetch all data in a pipeline
        Sidekiq.redis do |conn|
          pipe_results = conn.pipelined do |pipe|
            keys.each { |key| pipe.hgetall(key) }
          end.as(Array(Redis::RedisValue))

          timestamps.each_with_index do |ts, i|
            raw_data = pipe_results[i].as(Array(Redis::RedisValue))
            next if raw_data.empty?

            # Convert Array to Hash
            data = Hash(String, String).new
            raw_data.each_slice(2) do |pair|
              field = pair[0].to_s
              value = pair[1].to_s
              data[field] = value
            end

            result[ts] = data unless data.empty?
          end
        end

        result
      end

      # Generate all minute timestamps between start and end time
      private def self.generate_timestamps(start_time : Time, end_time : Time) : Array(Int64)
        timestamps = [] of Int64
        current = start_time.at_beginning_of_minute

        while current <= end_time
          timestamps << current.to_unix
          current += 1.minute
        end

        timestamps
      end

      # Aggregate metrics data for display
      # Returns totals for success, failure, total_ms across all timestamps
      def self.aggregate(data : Hash(Int64, Hash(String, String))) : NamedTuple(success: Int64, failure: Int64, total_ms: Float64)
        success = 0_i64
        failure = 0_i64
        total_ms = 0.0

        data.each_value do |metrics|
          success += metrics["s"]?.try(&.to_i64) || 0_i64
          failure += metrics["f"]?.try(&.to_i64) || 0_i64
          total_ms += metrics["ms"]?.try(&.to_f64) || 0.0
        end

        {success: success, failure: failure, total_ms: total_ms}
      end
    end
  end
end
