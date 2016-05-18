require "./pool/connection"
require "./sidekiq/*"

require "redis"

module Sidekiq
  class Connection
    # Set up Sidekiq to use the given ConnectionPool to connect to Redis
    #
    #     Sidekiq::Redis.new(ConnectionPool.new(capacity: 5, timeout: 5) { Redis.new("localhost", 6379) }
    #
    def initialize(@pool = ConnectionPool(Redis).new { Redis.new })
    end

    def with(&block : Redis -> Redis::RedisValue)
      @pool.connection(&block)
    end
  end
end
