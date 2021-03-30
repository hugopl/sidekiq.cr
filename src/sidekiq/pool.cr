require "uri"
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
    property hostname : String
    property port : Int32
    property db : Int32
    property pool_size : Int32
    property pool_timeout : Float64
    property password : String?

    DEFAULT_HOST = "localhost"
    DEFAULT_PORT = 6379

    def initialize(@hostname = DEFAULT_HOST, @port = DEFAULT_PORT, @db = 0, @pool_size = 26, @pool_timeout = 5.0, @password = nil)
      env_var = ENV["REDIS_PROVIDER"]?
      initialize_from_env_var(env_var) if env_var
    end

    private def initialize_from_env_var(env_var : String)
      url = ENV[env_var]? || raise ArgumentError.new("#{env_var} environment variable must contain a Redis URL")

      redis_url = URI.parse(url)
      @hostname = redis_url.host || DEFAULT_HOST
      @port = redis_url.port || DEFAULT_PORT
      @password = redis_url.password
      redis_url_path = redis_url.path
      return if redis_url_path.nil? || redis_url_path.size <= 1

      @db = redis_url_path[1..].to_i? || raise ArgumentError.new("Invalid Redis DB value '#{redis_url_path[1..]}', should be a number from 0 to 15")
    end

    def new_client
      Redis.new(host: hostname, port: port, password: password, database: db)
    end

    def new_pool
      Pool.new(self)
    end
  end

  class Pool
    @pool : ConnectionPool(Redis)

    # Set up a pool of connections to Redis on localhost:6379:
    #
    #     Sidekiq::Pool.new(5)
    #
    def initialize(size : Int32)
      initialize(RedisConfig.new(pool_size: size))
    end

    def initialize(cfg : RedisConfig)
      @pool = Redis::PooledClient.new(host: cfg.hostname,
        port: cfg.port,
        password: cfg.password,
        database: cfg.db,
        pool_size: cfg.pool_size,
        pool_timeout: cfg.pool_timeout).pool
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
      conn = @pool.checkout
      yield conn
    ensure
      @pool.checkin(conn) if conn
    end
  end
end
