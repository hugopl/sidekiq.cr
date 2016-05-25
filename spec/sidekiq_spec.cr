require "./spec_helper"

describe Sidekiq do
  describe "basics" do
    it "has a version" do
      Sidekiq::VERSION.should_not be_nil
    end
  end

  describe "float formatting" do
    it "preserves precision" do
      time = 1464132168.59994102_f64
      time.to_s.should eq("1464132168.59994102")

      num = 1464132168.65_f64
      num.to_s.should eq("1464132168.65000010")
    end
  end

  describe "pool" do
    it "works" do
      t = Time.now
      pool = ConnectionPool.new { Redis.new }
      pool.connection do |conn|
        conn.set("foo", t)
      end
      result = pool.connection do |conn|
        conn.get("foo")
      end
      result.should eq(t.to_s)
    end
  end

  describe "redis pooling" do
    it "works" do
      r = Sidekiq::Pool.new
      r.redis do |conn|
        conn.get("mike")
        conn.set("mike", "bob")
        conn.get("mike")
      end

      results = r.redis do |conn|
        conn.multi do |multi|
          multi.get("mike")
          multi.get("bob")
        end
      end
      arr = results.as(Array)
      arr[0]?.should eq("bob")
      arr[1]?.should be_nil
    end
  end
end
