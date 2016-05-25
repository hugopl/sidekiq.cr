require "./spec_helper"

describe Sidekiq::Job do
  describe "serialization" do
    it "deserializes a simple job" do
      r = Sidekiq::Pool.new
      str = r.redis do |conn|
        data = File.read("spec/queue.bin")
        conn.del("queue:default")
        conn.restore("queue:default", 10000, data, false)
        conn.llen("queue:default").should eq(1)
        conn.lpop("queue:default")
      end.as(String)

      hash = JSON.parse(str)
      hash.size.should eq(8)
    end

    it "deserializes a retry" do
      r = Sidekiq::Pool.new
      results = r.redis do |conn|
        data = File.read("spec/retry.bin")
        conn.del("retry")
        conn.restore("retry", 10000, data, false)
        conn.zcard("retry").should eq(1)
        conn.zrangebyscore("retry", "-inf", "inf")
      end.as(Array)

      results.size.should eq(1)
      str = results[0].as(String)
      hash = JSON.parse(str)
      hash.size.should eq(13)
    end
  end
end
