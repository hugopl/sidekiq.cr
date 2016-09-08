require "./sidekiq/pool"
require "./sidekiq/job"
require "./sidekiq/middleware"
require "./sidekiq/types"
require "./sidekiq/client"
require "./sidekiq/worker"
require "./sidekiq/logger"

module Sidekiq
  NAME    = "Sidekiq"
  VERSION = "0.6.0"
  LICENSE = "Licensed for use under the terms of the GNU LGPL-3.0 license."

  def self.redis
    Sidekiq::Client.default_context.pool.redis do |conn|
      yield conn
    end
  end
end
