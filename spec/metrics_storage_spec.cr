require "./spec_helper"
require "../src/sidekiq/metrics"

describe Sidekiq::Metrics::Query do
  describe ".record" do
    it "increments success count for successful jobs" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("TestWorker", 100.0, true, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis(&.hget(key, "s").should(eq("1")))
    end

    it "increments failure count for failed jobs" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("TestWorker", 100.0, false, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis(&.hget(key, "f").should(eq("1")))
    end

    it "accumulates total execution time in milliseconds" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("TestWorker", 150.5, true, timestamp)
      Sidekiq::Metrics::Query.record("TestWorker", 200.0, true, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis do |conn|
        ms = conn.hget(key, "ms").not_nil!.to_f
        ms.should be_close(350.5, 0.01)
      end
    end

    it "increments the correct histogram bucket" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      # 100ms should be bucket 4 (67-101ms)
      Sidekiq::Metrics::Query.record("TestWorker", 100.0, true, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis(&.hget(key, "h4").should(eq("1")))
    end

    it "sets TTL on the metrics key" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("TestWorker", 100.0, true, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis do |conn|
        ttl = conn.ttl(key)
        # TTL should be set and positive (within 72 hours)
        ttl.should be > 0
        ttl.should be <= Sidekiq::Metrics::DEFAULT_RETENTION
      end
    end

    it "adds job class to the classes set" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("MyApp::EmailWorker", 50.0, true, timestamp)

      Sidekiq.redis do |conn|
        members = conn.smembers(Sidekiq::Metrics::CLASSES_KEY)
        members.should contain("MyApp::EmailWorker")
      end
    end

    it "does not record execution time for failed jobs" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("TestWorker", 100.0, false, timestamp)

      key = Sidekiq::Metrics.key_for("TestWorker", timestamp)
      Sidekiq.redis do |conn|
        # ms should not be set for failures
        conn.hget(key, "ms").should be_nil
        # histogram should not be updated for failures
        conn.hget(key, "h4").should be_nil
        # but failure count should be incremented
        conn.hget(key, "f").should eq("1")
      end
    end
  end

  describe ".job_classes" do
    it "returns all job classes with metrics" do
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("Worker1", 50.0, true, timestamp)
      Sidekiq::Metrics::Query.record("Worker2", 100.0, true, timestamp)
      Sidekiq::Metrics::Query.record("Worker3", 150.0, false, timestamp)

      classes = Sidekiq::Metrics::Query.job_classes
      classes.should contain("Worker1")
      classes.should contain("Worker2")
      classes.should contain("Worker3")
    end
  end

  describe ".fetch" do
    it "retrieves metrics for a job class within a time range" do
      # Record metrics at two different minutes
      time1 = Time.utc(2025, 11, 25, 14, 30, 0)
      time2 = Time.utc(2025, 11, 25, 14, 31, 0)
      ts1 = Sidekiq::Metrics.minute_timestamp(time1)
      ts2 = Sidekiq::Metrics.minute_timestamp(time2)

      Sidekiq::Metrics::Query.record("FetchWorker", 100.0, true, ts1)
      Sidekiq::Metrics::Query.record("FetchWorker", 200.0, true, ts1)
      Sidekiq::Metrics::Query.record("FetchWorker", 150.0, true, ts2)

      start_time = Time.utc(2025, 11, 25, 14, 29, 0)
      end_time = Time.utc(2025, 11, 25, 14, 32, 0)

      result = Sidekiq::Metrics::Query.fetch("FetchWorker", start_time, end_time)

      result.size.should eq(2)
      result[ts1]?.should_not be_nil
      result[ts2]?.should_not be_nil
    end
  end
end
