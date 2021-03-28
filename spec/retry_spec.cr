require "./spec_helper"
require "../src/sidekiq/server/retry_jobs"

describe "retry" do
  it "works" do
    ctx = MockContext.new
    job = Sidekiq::Job.new
    job.queue = "default"
    job.klass = "MyWorker"
    job.args = "1"
    rt = Sidekiq::Middleware::RetryJobs.new

    time = Time.local
    Timecop.freeze(time) do
      expect_raises(Exception) do
        rt.call(job, ctx) { raise "boom" }
      end
    end

    POOL.redis { |c| c.llen("queue:default").should eq(0) }
    POOL.redis { |c| c.zcard("retry").should eq(1) }
    value, _score = POOL.redis { |c| c.zrange("retry", 0, -1, with_scores: true) }.as(Array)
    hash = JSON.parse(value.as(String))
    hash["error_message"].should eq("boom")
    hash["error_class"].should eq("Exception")
    # Cut then to integer to avoid false positives on float comparisson.
    hash["failed_at"].as_f.to_i.should eq(time.to_unix_f.to_i)
    hash["retried_at"].as_f.to_i.should eq(time.to_unix_f.to_i)
    hash["retry_count"].should eq(1)

    # Crash it again and check retried_at/failed_at/retry_count
    future = time + 1.day
    Timecop.freeze(future) do
      expect_raises(Exception) do
        rt.call(job, ctx) { raise "boom" }
      end
    end
    value, _score = POOL.redis { |c| c.zrange("retry", 1, -1, with_scores: true) }.as(Array)
    hash = JSON.parse(value.as(String))
    hash["failed_at"].as_f.to_i.should eq(time.to_unix_f.to_i)
    hash["retried_at"].as_f.to_i.should eq(future.to_unix_f.to_i)
    hash["retry_count"].should eq(2)
  end
end
