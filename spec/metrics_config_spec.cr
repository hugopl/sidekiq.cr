require "./spec_helper"
require "../src/sidekiq/server"
require "../src/sidekiq/metrics"

describe "Sidekiq::Server metrics configuration" do
  describe "metrics_enabled" do
    it "defaults to false" do
      server = Sidekiq::Server.new
      server.metrics_enabled.should be_false
    end

    it "can be set to true" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true
      server.metrics_enabled.should be_true
    end
  end

  describe "metrics_retention" do
    it "defaults to 72 hours (259200 seconds)" do
      server = Sidekiq::Server.new
      server.metrics_retention.should eq(259200)
    end

    it "can be configured to custom value" do
      server = Sidekiq::Server.new
      server.metrics_retention = 86400 # 24 hours
      server.metrics_retention.should eq(86400)
    end
  end

  describe "middleware integration" do
    it "does not include metrics middleware when disabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = false

      # Check middleware chain doesn't contain Metrics
      has_metrics = server.server_middleware.entries.any?(Sidekiq::Middleware::Metrics)
      has_metrics.should be_false
    end

    it "includes metrics middleware when enabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Check middleware chain contains Metrics
      has_metrics = server.server_middleware.entries.any?(Sidekiq::Middleware::Metrics)
      has_metrics.should be_true
    end

    it "prepends metrics middleware as first in chain when enabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Metrics middleware should be first (runs outermost, wraps all others)
      first = server.server_middleware.entries.first?
      first.should_not be_nil
      first.should be_a(Sidekiq::Middleware::Metrics)
    end

    it "records metrics for jobs when enabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      job = Sidekiq::Job.new
      job.klass = "ConfigTestWorker"
      ctx = MockContext.new

      Sidekiq::Processor.new(server)

      # Execute job through middleware chain
      result = server.server_middleware.invoke(job, ctx) { true }
      result.should be_true

      # Verify metrics were recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("ConfigTestWorker", timestamp)

      Sidekiq.redis(&.hget(key, "s").should(eq("1")))
    end

    it "does not record metrics for jobs when disabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = false

      job = Sidekiq::Job.new
      job.klass = "DisabledMetricsWorker"
      ctx = MockContext.new

      Sidekiq::Processor.new(server)

      # Execute job through middleware chain
      result = server.server_middleware.invoke(job, ctx) { true }
      result.should be_true

      # Verify NO metrics were recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("DisabledMetricsWorker", timestamp)

      Sidekiq.redis(&.hget(key, "s").should(be_nil))
    end
  end
end
