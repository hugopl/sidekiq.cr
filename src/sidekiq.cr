require "./sidekiq/pool"
require "./sidekiq/version"

class Sidekiq
  getter concurrency

  def initialize(@concurrency = 5, @pool = Sidekiq::Pool.new)
  end

  def run_server
    concurrency.times do |x|
      spawn do
        puts x
        exit
      end
    end
  end
end
