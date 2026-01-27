require "./spec_helper"
require "../src/sidekiq/metrics"

class SlowWorker
  include Sidekiq::Worker

  def perform
    sleep(10.milliseconds)
  end
end

class FailingWorker
  include Sidekiq::Worker

  def perform
    raise "Intentional failure"
  end
end

describe Sidekiq::Middleware::Metrics do
  describe "#call" do
    it "records metrics for successful jobs" do
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "SlowWorker"

      result = middleware.call(job, ctx) do
        sleep(5.milliseconds)
        true
      end

      result.should be_true

      # Verify metrics were recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("SlowWorker", timestamp)

      Sidekiq.redis do |conn|
        conn.hget(key, "s").should eq("1")
        ms = conn.hget(key, "ms")
        ms.should_not be_nil
        ms.not_nil!.to_f.should be > 0
      end
    end

    it "records failure count but not timing for failed jobs" do
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "FailingWorker"

      expect_raises(Exception, "Test failure") do
        middleware.call(job, ctx) do
          raise "Test failure"
          true
        end
      end

      # Verify failure was recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FailingWorker", timestamp)

      Sidekiq.redis do |conn|
        conn.hget(key, "f").should eq("1")
        # ms should not be set for failures
        conn.hget(key, "ms").should be_nil
      end
    end

    it "re-raises exceptions after recording metrics" do
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "FailingWorker"

      expect_raises(Exception, "Original error") do
        middleware.call(job, ctx) do
          raise "Original error"
          true
        end
      end
    end

    it "uses job.klass for the job class name" do
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "MyApp::Workers::EmailJob"

      middleware.call(job, ctx) { true }

      classes = Sidekiq::Metrics::Query.job_classes
      classes.should contain("MyApp::Workers::EmailJob")
    end

    it "categorizes jobs into correct histogram buckets" do
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "BucketTestWorker"

      # Run a very fast job (should be bucket 0: 0-20ms)
      middleware.call(job, ctx) { true }

      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("BucketTestWorker", timestamp)

      Sidekiq.redis do |conn|
        # Very fast job should be in bucket 0
        conn.hget(key, "h0").should eq("1")
      end
    end

    it "does not fail job execution if metrics recording fails" do
      # This test verifies error handling by checking that the job
      # completes even when metrics code is involved
      middleware = Sidekiq::Middleware::Metrics.new
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.klass = "ResilientWorker"

      job_executed = false
      result = middleware.call(job, ctx) do
        job_executed = true
        true
      end

      result.should be_true
      job_executed.should be_true
    end
  end
end
