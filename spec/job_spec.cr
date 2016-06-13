require "./spec_helper"

describe Sidekiq::Job do
  describe "serialization" do
    requires_redis(:>=, "3.2") do
      it "deserializes a simple job" do
        load_fixtures("ruby_compat")

        r = Sidekiq::Pool.new
        str = r.redis do |conn|
          conn.lpop("queue:default")
        end.as(String)

        hash = JSON.parse(str)
        hash.size.should eq(7)
      end

      it "deserializes a retry" do
        load_fixtures("ruby_compat")

        r = Sidekiq::Pool.new
        results = r.redis do |conn|
          conn.zrangebyscore("retry", "-inf", "inf")
        end.as(Array)

        results.size.should eq(1)
        str = results[0].as(String)
        hash = JSON.parse(str).as_h
        hash.size.should eq(11)

        job = Sidekiq::Job.new
        job.load(hash)
        aft = job.to_h
        hash.keys.each do |key|
          if key =~ /at/
            hf = hash[key].as(Float64)
            af = aft[key].as(Float64)
            (hf * 1000).to_i64.should eq((af * 1000).to_i64)
          else
            hash[key].should eq(aft[key])
          end
        end
      end
    end
  end
end
