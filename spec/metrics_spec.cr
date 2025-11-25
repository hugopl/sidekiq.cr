require "./spec_helper"
require "../src/sidekiq/metrics"

describe Sidekiq::Metrics::Histogram do
  describe ".bucket_for" do
    it "returns bucket 0 for jobs under 20ms" do
      Sidekiq::Metrics::Histogram.bucket_for(0.0).should eq(0)
      Sidekiq::Metrics::Histogram.bucket_for(10.0).should eq(0)
      Sidekiq::Metrics::Histogram.bucket_for(19.9).should eq(0)
    end

    it "returns bucket 1 for jobs 20-30ms" do
      Sidekiq::Metrics::Histogram.bucket_for(20.0).should eq(1)
      Sidekiq::Metrics::Histogram.bucket_for(25.0).should eq(1)
      Sidekiq::Metrics::Histogram.bucket_for(29.9).should eq(1)
    end

    it "returns bucket 2 for jobs 30-45ms" do
      Sidekiq::Metrics::Histogram.bucket_for(30.0).should eq(2)
      Sidekiq::Metrics::Histogram.bucket_for(40.0).should eq(2)
      Sidekiq::Metrics::Histogram.bucket_for(44.9).should eq(2)
    end

    it "returns correct bucket for ~100ms jobs" do
      # Bucket 4 is 67-101ms
      Sidekiq::Metrics::Histogram.bucket_for(100.0).should eq(4)
    end

    it "returns correct bucket for ~500ms jobs" do
      # Bucket 8 is 342-513ms
      Sidekiq::Metrics::Histogram.bucket_for(500.0).should eq(8)
    end

    it "returns correct bucket for ~1 second jobs" do
      # Bucket 10 is 769-1154ms
      Sidekiq::Metrics::Histogram.bucket_for(1000.0).should eq(10)
    end

    it "returns last bucket for very slow jobs" do
      Sidekiq::Metrics::Histogram.bucket_for(15000.0).should eq(17)
      Sidekiq::Metrics::Histogram.bucket_for(100000.0).should eq(17)
    end

    it "handles edge cases at bucket boundaries" do
      # At exactly 20ms, should be bucket 1
      Sidekiq::Metrics::Histogram.bucket_for(20.0).should eq(1)
      # At exactly 30ms, should be bucket 2
      Sidekiq::Metrics::Histogram.bucket_for(30.0).should eq(2)
    end
  end

  describe "BUCKET_BOUNDARIES" do
    it "has 17 boundaries (for 18 buckets)" do
      Sidekiq::Metrics::Histogram::BUCKET_BOUNDARIES.size.should eq(17)
    end

    it "starts at 20ms" do
      Sidekiq::Metrics::Histogram::BUCKET_BOUNDARIES.first.should eq(20.0)
    end

    it "follows 1.5x exponential scaling" do
      boundaries = Sidekiq::Metrics::Histogram::BUCKET_BOUNDARIES
      # Check first few boundaries follow 1.5x pattern
      boundaries[0].should eq(20.0)
      boundaries[1].should eq(30.0)  # 20 * 1.5
      boundaries[2].should eq(45.0)  # 30 * 1.5
    end
  end

  describe "BUCKET_COUNT" do
    it "equals 18" do
      Sidekiq::Metrics::Histogram::BUCKET_COUNT.should eq(18)
    end
  end
end

describe Sidekiq::Metrics do
  describe ".minute_timestamp" do
    it "truncates time to minute boundary" do
      time = Time.utc(2025, 11, 25, 14, 35, 42)
      timestamp = Sidekiq::Metrics.minute_timestamp(time)
      # Should be truncated to 14:35:00
      timestamp.should eq(Time.utc(2025, 11, 25, 14, 35, 0).to_unix)
    end

    it "returns unix timestamp" do
      time = Time.utc(2025, 11, 25, 14, 35, 0)
      timestamp = Sidekiq::Metrics.minute_timestamp(time)
      timestamp.should eq(time.to_unix)
    end
  end

  describe ".key_for" do
    it "generates correct Redis key format" do
      timestamp = Time.utc(2025, 11, 25, 14, 35, 0).to_unix
      key = Sidekiq::Metrics.key_for("HardWorker", timestamp)
      key.should eq("sidekiq:j:HardWorker:#{timestamp}")
    end

    it "handles job class names with namespaces" do
      timestamp = Time.utc(2025, 11, 25, 14, 35, 0).to_unix
      key = Sidekiq::Metrics.key_for("MyApp::Workers::EmailJob", timestamp)
      key.should eq("sidekiq:j:MyApp::Workers::EmailJob:#{timestamp}")
    end
  end
end
