require "pool/connection"
require "redis"

module Sidekiq
  class Pool
    # Set up a pool of connections to Redis on localhost:6379:
    #
    #     Sidekiq::Pool.new(5)
    #
    # or, to control the entire set of objects, pass a block which returns a ConnectionPool(Redis):
    #
    #    Sidekiq::Pool.new do
    #      ConnectionPool(Redis).new(capacity: 5, timeout: 5) do
    #        Redis.new(host: "localhost", port: 6379, password: "xyzzy")
    #      end
    #    end
    #
    def initialize(capacity = 5)
      @pool = ConnectionPool(Redis).new(capacity: capacity) do
        Redis.new(host: "localhost", port: 6379)
      end
    end

    def initialize(&block)
      @pool = yield
    end

    # Execute one or more Redis operations:
    #
    #     pool.redis do |conn|
    #       conn.set("mike", "rules") => "OK"
    #       conn.get("mike") => "rules"
    #     end
    #
    # Or as a transaction:
    #
    #     pool.redis do |conn|
    #       conn.multi do |multi|
    #         multi.set("mike", "rules")
    #         multi.get("mike")
    #       end => ["OK", "mike"]
    #     end
    #
    def redis(&block : Redis -> Redis::RedisValue)
      @pool.connection(&block)
    end
  end
end
