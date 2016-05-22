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

    def initialize(@environment = "development", @queues = ["default"], @concurrency = 25, @logger = Sidekiq::Logger.build)
      @alive = true
      @middleware = Sidekiq::Server.default_middleware

      @error_handlers = [] of Sidekiq::ExceptionHandler::Base
      @error_handlers << Sidekiq::ExceptionHandler::Logger.new(@logger)

      @pool = Sidekiq::Client.default = Sidekiq::Pool.new(@concurrency + 2)
      @fetcher = Sidekiq::BasicFetch.new(@pool.not_nil!, @queues)
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

    def banner
%{
         m,
         `$b
    .ss,  $$:         .,d$
    `$$P,d$P'    .,md$P"'
     ,$$$$$bmmd$$$P^'
   .d$$$$$$$$$$P'
   $$^' `"^$$$'       ____  _     _      _    _
   $:     ,$$:       / ___|(_) __| | ___| | _(_) __ _
   `b     :$$        \___ \| |/ _` |/ _ \ |/ / |/ _` |
          $$:         ___) | | (_| |  __/   <| | (_| |
          $$         |____/|_|\__,_|\___|_|\_\_|\__, |
        .d$$                                       |_|
}
    end

    def print_banner
      if STDOUT.tty? && environment == "development"
        puts "\e[#{31}m"
        puts banner
        puts "\e[0m"
      end
    end

    def start
      print_banner

      logger.info "Sidekiq v#{Sidekiq::VERSION} in #{{{`crystal -v`.strip.stringify}}}"
      logger.info Sidekiq::LICENSE
      logger.info "Upgrade to Sidekiq Enterprise for more features and support: http://sidekiq.org"
      logger.info "Starting processing with #{concurrency} workers"

      raise "You must register one or more workers to execute jobs!" unless Sidekiq::Job.valid?
      concurrency.times do
        p = Sidekiq::Processor.new(self)
        @processors << p
        p.start
      end

      scheduler.start(self)
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
