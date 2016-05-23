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
      @middleware = Sidekiq::Server.default_middleware

      @error_handlers = [] of Sidekiq::ExceptionHandler::Base
      @error_handlers << Sidekiq::ExceptionHandler::Logger.new(@logger)

      @pool = Sidekiq::Client.default = Sidekiq::Pool.new(@concurrency + 2)
      @fetcher = Sidekiq::BasicFetch.new(@pool, @queues)
      @processors = [] of Sidekiq::Processor
      @scheduler = Sidekiq::Scheduled::Poller.new
    end

    @@chain : Sidekiq::Middleware::Chain = Sidekiq::Middleware::Chain.new.tap do |c|
      c.add Sidekiq::Middleware::Logger.new
      c.add Sidekiq::Middleware::RetryJobs.new
    end

    def self.default_middleware
      @@chain
    end

    def start
      raise "You must register one or more workers to execute jobs!" unless Sidekiq::Job.valid?
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
    end

    def heartbeat
    end
  end
end
