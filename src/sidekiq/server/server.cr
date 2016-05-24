require "./logger"
require "./fetch"
require "./processor"
require "./scheduled"
require "./middleware"

module Sidekiq
  class Server < Sidekiq::Context
    getter environment : String
    getter concurrency : Int32
    getter fetcher : Sidekiq::Fetch
    getter scheduler : Sidekiq::Scheduled::Poller
    getter pool : Sidekiq::Pool
    getter middleware : Sidekiq::Middleware::Chain
    getter error_handlers : Array(Sidekiq::ExceptionHandler::Base)
    getter processors : Array(Sidekiq::Processor)
    getter logger : ::Logger
    getter labels : Array(String)
    getter queues : Array(String)
    getter tag : String
    getter busy : Int32

    def initialize(@environment = "development", @queues = ["default"],
                   @concurrency = 25, @logger = Sidekiq::Logger.build)
      @busy = 0
      @tag = ""
      @labels = [] of String
      @alive = true
      @middleware = Sidekiq::Middleware::Chain.new.tap do |c|
        c.add Sidekiq::Middleware::Logger.new
        c.add Sidekiq::Middleware::RetryJobs.new
      end

      @error_handlers = [] of Sidekiq::ExceptionHandler::Base
      @error_handlers << Sidekiq::ExceptionHandler::Logger.new(@logger)

      @pool = Sidekiq::Pool.new(@concurrency + 2)
      @processors = [] of Sidekiq::Processor
      @scheduler = Sidekiq::Scheduled::Poller.new
      @fetcher = Sidekiq::BasicFetch.new(@queues)
    end

    def server_middleware
      middleware
    end

    def client_middleware
      Sidekiq::Client.middleware
    end

    def redis=(pool : ConnectionPool(Redis))
      @pool = Sidekiq::Pool.new(pool)
    end

    def validate
      raise "You must register one or more workers to execute jobs!" unless Sidekiq::Job.valid?
    end

    def start
      validate
      concurrency.times do
        p = Sidekiq::Processor.new(self)
        @processors << p
        p.start
      end

      scheduler.start(self)
    end

    def stopping?
      !@alive
    end

    def request_stop
      @alive = false
    end

    def processor_stopped(processor)
      @processors.delete(processor)
    end

    def processor_died(processor, ex)
      @processors.delete(processor)
      return if stopping?

      p = Sidekiq::Processor.new(self)
      @processors << p
      p.start
      p
    end

    def heartbeat
    end
  end
end
