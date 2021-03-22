# require "sidekiq/cli"
require "../src/cli"

# This file is an example of how to start a Sidekiq.cr
# worker process to execute jobs.
#
# You must define one or more Sidekiq::Worker classes
# before you start the server!
class CrystalWorker
  include Sidekiq::Worker
  sidekiq_options do |job|
    job.queue = "default"
    job.retry = true
  end

  def perform(x : Int64)
    logger.info { "hello!" }
  end
end

class SomeClientMiddleware < Sidekiq::Middleware::ClientEntry
  def call(job, ctx) : Bool
    ctx.logger.info { "Pushing job #{job.jid}" }
    yield
    true
  end
end

class SomeServerMiddleware < Sidekiq::Middleware::ServerEntry
  def call(job, ctx) : Bool
    ctx.logger.info { "Executing job #{job.jid}" }
    yield
    true
  end
end

cli = Sidekiq::CLI.new
server = cli.configure do |config|
  config.server_middleware.add SomeServerMiddleware.new
  config.client_middleware.add SomeClientMiddleware.new

  # The main thing you need to configure with Sidekiq.cr is how to connect to
  # Redis. The default is localhost:6379 and typically appropriate for local development.
  #
  # Redis location can be configured via the REDIS_PROVIDER env variable.
  # You set two variables:
  #   - REDIS_URL = "redis://:password@hostname:port/db"
  #   - REDIS_PROVIDER = "REDIS_URL"
  #
  # Sidekiq looks for the REDIS_PROVIDER env variable to tell it which env variable holds the
  # actual Redis URL.  This works perfectly when using a Redis SaaS on Heroku, e.g., where the
  # SaaS add-on will set an env var like REDISTOGO_URL.  You just need to set REDIS_PROVIDER:
  #
  #   heroku config:set REDIS_PROVIDER=REDISTOGO_URL
  #
  # Redis location can also be set using the API
  config.redis = Sidekiq::RedisConfig.new("localhost", 6379)
end

# Push some jobs
CrystalWorker.async.perform(1_i64)
CrystalWorker.async.perform(2_i64)

# Run the server
cli.run(server)
