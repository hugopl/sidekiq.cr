require "uri"
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
    # Alternatively you can set environment variables to configure Redis:
    #
    #   MY_REDIS_URL=redis://:password@some.hostname.com:2435/
    #   REDIS_PROVIDER=MY_REDIS_URL
    #
    # Note that you set REDIS_PROVIDER to the **name** of the variable which contains the URL.
    #
    def initialize(capacity = 5, timeout = 5.0)
      hostname = "localhost"
      port = 6379
      password = nil

      if ENV["REDIS_PROVIDER"]?
        url = ENV[ENV["REDIS_PROVIDER"]]
        redis_url = URI.parse(url)
        hostname = redis_url.host.not_nil!
        port = redis_url.port
        password = redis_url.password
      end

      @pool = ConnectionPool(Redis).new(capacity: capacity, timeout: timeout) do
        Redis.new(host: hostname, port: port, password: password)
      end
    end

    def initialize(pool : ConnectionPool(Redis))
      @pool = pool
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
