require "./spec_helper"

describe "retry" do
  it "works" do
    POOL.redis do |c|
      c.flushdb
    end
    ctx = MockContext.new
    job = Sidekiq::Job.new
    job.queue = "default"
    job.klass = "MyWorker"
    job.args = "1"
    rt = Sidekiq::Middleware::RetryJobs.new

    expect_raises do
      rt.call(job, ctx) do
        raise "boom"
      end
    end

    POOL.redis { |c| c.llen("queue:default").should eq(0) }
    POOL.redis { |c| c.zcard("retry").should eq(1) }
    value, score = POOL.redis { |c| c.zrange("retry", 0, -1, with_scores: true) }.as(Array)
    hash = JSON.parse(value.as(String))
    hash["error_message"].should eq("boom")
    hash["error_class"].should eq("Exception")
    hash["failed_at"].should be_truthy
  end
end
