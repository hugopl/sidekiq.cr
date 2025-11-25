module Sidekiq
  module Metrics
    module Histogram
      # Number of histogram buckets
      BUCKET_COUNT = 18

      # Bucket boundaries in milliseconds
      # Each boundary represents the upper limit of the previous bucket
      # Bucket 0: 0-20ms
      # Bucket 1: 20-30ms (20 * 1.5)
      # Bucket 2: 30-45ms (30 * 1.5)
      # ... and so on with 1.5x exponential scaling
      BUCKET_BOUNDARIES = begin
        boundaries = [] of Float64
        value = 20.0
        17.times do
          boundaries << value
          value = (value * 1.5).round(0)
        end
        boundaries
      end

      # Find the appropriate bucket index for a given duration in milliseconds
      # Returns 0 for fastest jobs, up to BUCKET_COUNT-1 for slowest
      def self.bucket_for(duration_ms : Float64) : Int32
        BUCKET_BOUNDARIES.each_with_index do |boundary, index|
          return index if duration_ms < boundary
        end
        # If duration exceeds all boundaries, return the last bucket
        BUCKET_COUNT - 1
      end

      # Get the bucket field name for Redis storage
      def self.bucket_field(bucket_index : Int32) : String
        "h#{bucket_index}"
      end
    end
  end
end
