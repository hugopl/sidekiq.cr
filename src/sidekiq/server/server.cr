require "./logger"
require "./fetch"
require "./processor"
require "./middleware"

module Sidekiq
  class Server
    getter concurrency : Int32
    getter fetcher : Sidekiq::Fetch
    getter pool : Sidekiq::Pool
    getter middleware : Sidekiq::Middleware::Chain
    getter error_handlers : Array(Sidekiq::ExceptionHandler::Base)
    getter processors : Array(Sidekiq::Processor)
    getter logger : ::Logger

    def initialize(@queues = ["default"], @concurrency = 25, @logger = Sidekiq::Logger.build)
      @alive = true
      @middleware = Sidekiq::Middleware::Chain.new
      @middleware.add Sidekiq::Middleware::Logger.new
      @pool = Sidekiq::Client.default = Sidekiq::Pool.new(@concurrency + 2)
      @fetcher = Sidekiq::BasicFetch.new(@pool.not_nil!, @queues)
      @error_handlers = [] of Sidekiq::ExceptionHandler::Base
      @error_handlers << Sidekiq::ExceptionHandler::Logger.new(@logger)
      @processors = [] of Sidekiq::Processor
    end

    def start
      logger.info "Starting processing with #{concurrency} workers"
      concurrency.times do
        p = Sidekiq::Processor.new(self)
        @processors << p
        p.start
      end
    end

    def processor_stopped(processor)
      @processors.delete(processor)
    end

    def processor_died(processor, ex)
      @processors.delete(processor)

      p = Sidekiq::Processor.new(self)
      @processors << p
      p.start
    end

    def monitor
      Signal::INT.trap do
        @alive = false
      end
      Signal::TERM.trap do
        @alive = false
      end

      logger.info "Press Ctrl-C to stop"
      spawn do
        while @alive
          heartbeat
          sleep 5
        end
      end

      while @alive
        sleep 1
      end
      logger.info "Done, bye!"
      exit(0)
    end

    def heartbeat
    end
  end
end
