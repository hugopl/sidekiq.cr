class Sidekiq
  class Manager
    getter concurrency
    property fetcher
    property scheduler
    property logger
    property pool

    def initializer(@queues = ["default"], @concurrency = 5)
      @logger = Sidekiq::Logger.build
      @pool = Sidekiq::Pool.new(@concurrency + 2)
      @fetcher = Sidekiq::BasicFetch.new(@logger, @pool, @queues)
    end

    def configure
      yield self
    end

    def start
      concurrency.times do
        p = Sidekiq::Processor.new
        p.start
      end
    end

    def monitor
      loop do
        sleep 5
        heartbeat
      end
    end

    def heartbeat
      puts "ba-bump"
    end
  end
end
