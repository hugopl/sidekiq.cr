require "./spec_helper"
require "../src/sidekiq/server"
require "../src/sidekiq/metrics"

class MetricsTestWorker
  include Sidekiq::Worker

  def perform(duration_ms : Int32)
    sleep((duration_ms / 1000.0).seconds)
  end
end

class FastMetricsWorker
  include Sidekiq::Worker

  def perform
    # Very fast job
  end
end

class FailingMetricsWorker
  include Sidekiq::Worker

  def perform
    raise "Integration test failure"
  end
end

describe "Metrics Integration" do
  describe "end-to-end metrics recording with server" do
    it "records metrics for jobs processed through the full pipeline" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Push a job
      client = Sidekiq::Client.new
      job = Sidekiq::Job.new
      job.klass = "FastMetricsWorker"
      jid = client.push(job)
      jid.should_not be_nil

      # Process the job
      processor = Sidekiq::Processor.new(server)
      processor.process_one

      # Verify metrics were recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FastMetricsWorker", timestamp)

      Sidekiq.redis do |conn|
        success = conn.hget(key, "s")
        success.should eq("1")

        ms = conn.hget(key, "ms")
        ms.should_not be_nil
        ms.not_nil!.to_f.should be >= 0

        # Should have a histogram bucket incremented
        has_histogram = false
        (0...Sidekiq::Metrics::Histogram::BUCKET_COUNT).each do |i|
          if conn.hget(key, Sidekiq::Metrics::Histogram::BUCKET_FIELDS[i])
            has_histogram = true
            break
          end
        end
        has_histogram.should be_true
      end

      # Verify job class was added to classes set
      classes = Sidekiq::Metrics::Query.job_classes
      classes.should contain("FastMetricsWorker")
    end

    it "does NOT record metrics when disabled" do
      server = Sidekiq::Server.new
      server.metrics_enabled = false

      # Push a job
      client = Sidekiq::Client.new
      job = Sidekiq::Job.new
      job.klass = "FastMetricsWorker"
      jid = client.push(job)
      jid.should_not be_nil

      # Process the job
      processor = Sidekiq::Processor.new(server)
      processor.process_one

      # Verify NO metrics were recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FastMetricsWorker", timestamp)

      Sidekiq.redis do |conn|
        # All fields should be nil when metrics are disabled
        conn.hget(key, "s").should be_nil
        conn.hget(key, "f").should be_nil
        conn.hget(key, "ms").should be_nil
      end
    end

    it "records failure metrics for jobs that raise exceptions" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Push a failing job
      client = Sidekiq::Client.new
      job = Sidekiq::Job.new
      job.klass = "FailingMetricsWorker"
      jid = client.push(job)
      jid.should_not be_nil

      # Process the job (will fail and retry)
      processor = Sidekiq::Processor.new(server)
      begin
        processor.process_one
      rescue Exception
        # Job will raise, that's expected
      end

      # Verify failure was recorded
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FailingMetricsWorker", timestamp)

      Sidekiq.redis do |conn|
        failure = conn.hget(key, "f")
        failure.should eq("1")

        # No timing data for failures
        ms = conn.hget(key, "ms")
        ms.should be_nil
      end
    end

    it "records multiple jobs from the same class" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Push multiple jobs
      client = Sidekiq::Client.new
      3.times do
        job = Sidekiq::Job.new
        job.klass = "FastMetricsWorker"
        client.push(job)
      end

      # Process all jobs
      processor = Sidekiq::Processor.new(server)
      3.times { processor.process_one }

      # Verify aggregated metrics
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FastMetricsWorker", timestamp)

      Sidekiq.redis do |conn|
        success = conn.hget(key, "s")
        success.should eq("3")

        ms = conn.hget(key, "ms")
        ms.should_not be_nil
        ms.not_nil!.to_f.should be > 0
      end
    end

    it "tracks metrics across different job classes" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Push jobs from different classes
      client = Sidekiq::Client.new

      job1 = Sidekiq::Job.new
      job1.klass = "FastMetricsWorker"
      client.push(job1)

      job2 = Sidekiq::Job.new
      job2.klass = "MetricsTestWorker"
      job2.args = "[5]"
      client.push(job2)

      # Process both jobs
      processor = Sidekiq::Processor.new(server)
      2.times { processor.process_one }

      # Verify both job classes are tracked
      classes = Sidekiq::Metrics::Query.job_classes
      classes.should contain("FastMetricsWorker")
      classes.should contain("MetricsTestWorker")

      # Verify separate metrics for each class
      timestamp = Sidekiq::Metrics.minute_timestamp

      Sidekiq.redis do |conn|
        key1 = Sidekiq::Metrics.key_for("FastMetricsWorker", timestamp)
        conn.hget(key1, "s").should eq("1")

        key2 = Sidekiq::Metrics.key_for("MetricsTestWorker", timestamp)
        conn.hget(key2, "s").should eq("1")
      end
    end

    it "sets TTL on metrics keys" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Push and process a job
      client = Sidekiq::Client.new
      job = Sidekiq::Job.new
      job.klass = "FastMetricsWorker"
      client.push(job)

      processor = Sidekiq::Processor.new(server)
      processor.process_one

      # Verify TTL is set
      timestamp = Sidekiq::Metrics.minute_timestamp
      key = Sidekiq::Metrics.key_for("FastMetricsWorker", timestamp)

      Sidekiq.redis do |conn|
        ttl = conn.ttl(key)
        ttl.should be > 0
        ttl.should be <= server.metrics_retention
      end
    end
  end

  describe "Query.fetch" do
    it "retrieves metrics data within time range" do
      server = Sidekiq::Server.new
      server.metrics_enabled = true

      # Record some metrics
      timestamp = Sidekiq::Metrics.minute_timestamp
      Sidekiq::Metrics::Query.record("FetchTestWorker", 100.0, true, timestamp)
      Sidekiq::Metrics::Query.record("FetchTestWorker", 200.0, true, timestamp)

      # Fetch the data
      start_time = Time.unix(timestamp) - 1.minute
      end_time = Time.unix(timestamp) + 1.minute

      result = Sidekiq::Metrics::Query.fetch("FetchTestWorker", start_time, end_time)

      result.should_not be_empty
      result[timestamp]?.should_not be_nil

      data = result[timestamp]
      data["s"].should eq("2")
      data["ms"].to_f.should be_close(300.0, 0.1)
    end
  end

  describe "Query.aggregate" do
    it "calculates totals across multiple timestamps" do
      timestamp1 = Sidekiq::Metrics.minute_timestamp
      timestamp2 = timestamp1 + 60

      Sidekiq::Metrics::Query.record("AggregateWorker", 100.0, true, timestamp1)
      Sidekiq::Metrics::Query.record("AggregateWorker", 200.0, true, timestamp1)
      Sidekiq::Metrics::Query.record("AggregateWorker", 150.0, true, timestamp2)
      Sidekiq::Metrics::Query.record("AggregateWorker", 50.0, false, timestamp2)

      start_time = Time.unix(timestamp1) - 1.minute
      end_time = Time.unix(timestamp2) + 1.minute

      data = Sidekiq::Metrics::Query.fetch("AggregateWorker", start_time, end_time)
      totals = Sidekiq::Metrics::Query.aggregate(data)

      totals[:success].should eq(3)
      totals[:failure].should eq(1)
      totals[:total_ms].should be_close(450.0, 0.1)
    end
  end
end
