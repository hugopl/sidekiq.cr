require "uri"
require "pool/connection"
require "redis"

module Sidekiq
  ##
  # Configures how Sidekiq connects to Redis.
  #
  #    Sidekiq::RedisConfig.new(hostname: "some.hostname.com", port: 2345, db: 14, password: "xyzzy")
  #
  # Alternatively you can set environment variables to configure Redis:
  #
  #   MY_REDIS_URL=redis://:password@some.hostname.com:2435/14
  #   REDIS_PROVIDER=MY_REDIS_URL
  #
  # Note that you set REDIS_PROVIDER to the **name** of the variable which contains the URL.
  class RedisConfig
    property! hostname : String
    property! port : Int32
    property! db : Int32
    property! pool_size : Int32
    property! pool_timeout : Float64
    property password : String?

    def initialize(@hostname = "localhost", @port = 6379, @db = 0, @pool_size = 5, @pool_timeout = 5.0, @password = nil)
      if ENV["REDIS_PROVIDER"]?
        url = ENV[ENV["REDIS_PROVIDER"]]
        redis_url = URI.parse(url)
        @hostname = redis_url.host.not_nil!
        @port = redis_url.port
        @password = redis_url.password
        if redis_url.path
          x = redis_url.path.not_nil!
          if x.size > 1
            begin
              @db = x[1..-1].to_i
            rescue ex : ArgumentError
              raise ArgumentError.new("Invalid Redis DB value '#{x[1..-1]}', should be a number from 0 to 15")
            end
          end
        end
        @password = redis_url.password
      end
    end

    def new_client
      Redis.new(host: hostname, port: port, password: password, database: db)
    end

    def new_pool
      Pool.new(self)
    end
  end

  class Pool

    # Set up a pool of connections to Redis on localhost:6379:
    #
    #     Sidekiq::Pool.new(5)
    #
    def initialize(size : Int32)
      initialize(RedisConfig.new(pool_size: size))
    end

    def initialize(redis_cfg : RedisConfig)
      @pool = ConnectionPool(Redis).new(capacity: redis_cfg.pool_size, timeout: redis_cfg.pool_timeout) do
        redis_cfg.new_client
      end
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
    def redis
      @pool.connection do |conn|
        yield conn
      end
    end
  end
end
