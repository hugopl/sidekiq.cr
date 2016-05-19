require "./spec_helper"

describe Sidekiq do
  describe "basics" do
    it "has a version" do
      Sidekiq::VERSION.should_not be_nil
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
      puts `redis-cli flushall`
      r = Sidekiq::Pool.new
      r.redis do |conn|
        conn.get("mike")
        conn.set("mike", "bob")
        conn.get("mike")
      end

      p(r.redis do |conn|
        conn.multi do |multi|
          multi.get("mike")
          multi.get("bob")
        end
      end)
    end
  end

end
