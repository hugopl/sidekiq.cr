require "./sidekiq/pool"
require "./sidekiq/job"
require "./sidekiq/middleware"
require "./sidekiq/types"
require "./sidekiq/client"
require "./sidekiq/worker"

module Sidekiq
  VERSION = "0.2.0"
  LICENSE = "Licensed for use under the terms of the GNU LGPL-3.0 license."
end
