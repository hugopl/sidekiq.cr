require "benchmark"
require "../middleware"
require "../metrics"

module Sidekiq
  module Middleware
    class Metrics < ServerEntry
      def call(job : Sidekiq::Job, ctx : Context, &) : Bool
        # Capture execution time
        duration_seconds = Benchmark.realtime do
          begin
            yield
          rescue ex
            # Record failure metrics (no timing)
            record_metrics(job.klass, 0.0, false)
            raise ex
          end
        end

        # Convert seconds to milliseconds
        duration_ms = duration_seconds.total_milliseconds

        # Record success metrics
        record_metrics(job.klass, duration_ms, true)

        true
      end

      private def record_metrics(job_class : String, duration_ms : Float64, success : Bool)
        Sidekiq::Metrics::Query.record(job_class, duration_ms, success)
      rescue ex : Exception
        # Log error but don't fail the job if metrics recording fails
        # The job execution itself should not be affected by metrics issues
        # TODO: Use ctx.logger when available in middleware context
      end
    end
  end
end
