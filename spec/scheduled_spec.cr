require "./spec_helper"
require "../src/sidekiq/server/scheduled"

describe "scheduler" do
  requires_redis(:>=, "3.2") do
    it "should schedule" do
      load_fixtures("ruby_compat")

      POOL.redis do |conn|
        conn.zcard("retry").should eq(1)
        conn.zcard("schedule").should eq(4)
        conn.llen("queue:default").should eq(4)
        conn.llen("queue:foo").should eq(2)
      end

      p = Sidekiq::Scheduled::Poller.new
      ctx = MockContext.new
      p.enqueue(ctx).should eq(5)

      POOL.redis do |conn|
        conn.zcard("retry").should eq(0)
        conn.zcard("schedule").should eq(0)
        conn.llen("queue:default").should eq(8)
        conn.llen("queue:foo").should eq(3)
      end
    end
  end
end
