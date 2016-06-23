require "secure_random"
require "./types"

module Sidekiq
  class Client
    class Context < Sidekiq::Context
      getter! pool : Sidekiq::Pool
      getter! logger : ::Logger

      def error_handlers
        [] of Sidekiq::ExceptionHandler::Base
      end

      def initialize
        @pool = RedisConfig.new.new_pool
        @logger = Sidekiq::Logger.build
      end

      def initialize(redis_cfg : Sidekiq::RedisConfig, logger : ::Logger? = nil)
        @pool = redis_cfg.new_pool
        @logger = logger || Sidekiq::Logger.build
      end

      def initialize(pool : Sidekiq::Pool, logger : ::Logger? = nil)
        @pool = pool
        @logger = logger || Sidekiq::Logger.build
      end
    end

    DEFAULT_MIDDLEWARE = Sidekiq::Middleware::Chain(Sidekiq::Middleware::ClientEntry).new

    @@default : Sidekiq::Context?

    def self.default_context=(ctx)
      @@default = ctx
    end

    def self.default_context : Sidekiq::Context
      @@default.not_nil!
    end

    def self.middleware
      DEFAULT_MIDDLEWARE
    end

    # #
    # Define client-side middleware:
    #
    #   client = Sidekiq::Client.new
    #   client.middleware do |chain|
    #     chain.use MyClientMiddleware
    #   end
    #
    def middleware(&block)
      yield @chain
      @chain
    end

    def middleware
      @chain
    end

    @chain : Sidekiq::Middleware::Chain(Sidekiq::Middleware::ClientEntry)
    @ctx : Sidekiq::Context
    @pool : Sidekiq::Pool

    # Sidekiq::Client normally uses the default Redis pool but you may
    # set a custom ConnectionPool if you want to shard your
    # Sidekiq jobs across several Redis instances (for scalability
    # reasons, e.g.)
    #
    #   c = Sidekiq::Client.new(Sidekiq::Pool.new)
    #
    # Generally this is only needed for very large Sidekiq installs processing
    # thousands of jobs per second.  I don't recommend sharding unless you
    # cannot scale any other way (e.g. splitting your app into smaller apps).
    def initialize(pool = nil)
      raise "Sidekiq client has not been configured yet" unless @@default
      @ctx = @@default.not_nil!
      @pool = pool || @ctx.pool
      @chain = DEFAULT_MIDDLEWARE.copy
    end

    # #
    # The main method used to push a job to Redis.  Accepts a number of options:
    #
    #   queue - the named queue to use, default 'default'
    #   class - the worker class to call, required
    #   args - an array of simple arguments to the perform method, must be JSON-serializable
    #   retry - whether to retry this job if it fails, default true or an integer number of retries
    #   backtrace - whether to save any error backtrace, default false
    #
    # All options must be strings, not symbols.  NB: because we are serializing to JSON, all
    # symbols in 'args' will be converted to strings.  Note that +backtrace: true+ can take quite a bit of
    # space in Redis; a large volume of failing jobs can start Redis swapping if you aren't careful.
    #
    # Returns a unique Job ID.  If middleware stops the job, nil will be returned instead.
    #
    # Example:
    #   push('queue' => 'my_queue', 'class' => MyWorker, 'args' => ['foo', 1, :bat => 'bar'])
    #
    def push(job : Sidekiq::Job)
      result = middleware.invoke(job, @ctx) do
        true
      end

      if result
        raw_push([job])
        job.jid
      end
    end

    # #
    # Push a large number of jobs to Redis.  In practice this method is only
    # useful if you are pushing thousands of jobs or more.  This method
    # cuts out the redis network round trip latency.
    #
    # Takes the same arguments as #push except that allargs is expected to be
    # an Array of Arrays.  All other keys are duplicated for each job.  Each job
    # is run through the client middleware pipeline and each job gets its own Job ID
    # as normal.
    #
    # Returns an array of the of pushed jobs' jids.  The number of jobs pushed can be less
    # than the number given if the middleware stopped processing for one or more jobs.
    def push_bulk(job : Sidekiq::Job, allargs : Array(String))
      payloads = allargs.map do |args|
        copy = Sidekiq::Job.new
        copy.jid = SecureRandom.hex(12)
        copy.klass = job.klass
        copy.queue = job.queue
        copy.args = args
        result = middleware.invoke(copy, @ctx) do
          !!copy
        end
        result ? copy : nil
      end.compact

      raw_push(payloads) if !payloads.empty?
      payloads.map { |payload| payload.jid }
    end

    def raw_push(payloads)
      @ctx.pool.redis do |conn|
        conn.multi do |multi|
          atomic_push(multi, payloads)
        end
      end
      true
    end

    def atomic_push(conn, payloads)
      if payloads.first.at
        all = [] of Redis::RedisValue
        payloads.each do |hash|
          at, hash.at = hash.at, nil
          all << at.not_nil!.epoch_f.to_s
          all << hash.to_json
        end
        conn.zadd("schedule", all)
      else
        q = payloads.first.queue
        now = Time.now
        to_push = payloads.map do |entry|
          entry.enqueued_at = now
          entry.to_json
        end
        conn.sadd("queues", q)
        conn.lpush("queue:#{q}", to_push)
      end
    end
  end
end
