require "./spec_helper"

describe Sidekiq::Job do
  describe "serialization" do
    requires_redis(:>=, "3.2") do
      it "deserializes a simple job" do
        load_fixtures("ruby_compat")

        str = POOL.redis do |conn|
          conn.lpop("queue:default")
        end.as(String)

        hash = JSON.parse(str)
        hash.size.should eq(7)
      end

      it "deserializes a retry" do
        load_fixtures("ruby_compat")

        results = POOL.redis do |conn|
          conn.zrangebyscore("retry", "-inf", "inf")
        end.as(Array)

        results.size.should eq(1)
        str = results[0].as(String)
        hash = JSON.parse(str).as_h
        hash.size.should eq(11)

        Sidekiq::Job.from_json(str)
      end
    end
  end
end
