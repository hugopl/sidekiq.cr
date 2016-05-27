require "./spec_helper"
require "../src/sidekiq/server/scheduled"

describe "scheduler" do
  requires_redis(:<, "3.2.0") do
    it "should schedule" do
      POOL.redis do |conn|
        data = File.read("spec/retry.bin")
        conn.del("retry", "queue:default")
        conn.restore("retry", 10000, data, false)
        conn.zcard("retry").should eq(1)
      end

      p = Sidekiq::Scheduled::Poller.new
      ctx = MockContext.new
      p.enqueue(ctx).should eq(1)

      POOL.redis do |conn|
        conn.zcard("retry").should eq(0)
        conn.llen("queue:default").should eq(1)
      end
    end
  end
end
