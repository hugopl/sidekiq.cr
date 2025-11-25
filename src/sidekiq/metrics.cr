require "./metrics/histogram"

module Sidekiq
  module Metrics
    # Redis key prefix for job metrics
    KEY_PREFIX = "sidekiq:j"

    # Redis key for tracking all job classes with metrics
    CLASSES_KEY = "sidekiq:j:classes"

    # Default retention period (72 hours in seconds)
    DEFAULT_RETENTION = 259200

    # Generate a minute-level timestamp (truncated to minute boundary)
    def self.minute_timestamp(time : Time = Time.utc) : Int64
      # Truncate to minute by zeroing out seconds
      time.at_beginning_of_minute.to_unix
    end

    # Generate Redis key for a job class at a specific minute
    def self.key_for(job_class : String, minute_timestamp : Int64) : String
      "#{KEY_PREFIX}:#{job_class}:#{minute_timestamp}"
    end
  end
end
