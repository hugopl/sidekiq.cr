require "./src/sidekiq/server/cli"

# This file is an example of how to start Sidekiq for Crystal.
# You must define one or more Sidekiq::Worker classes
# before you start the server!
class MyWorker
  include Sidekiq::Worker

  perform_types(Int64)
  def perform(x)
    logger.info "hello!"
  end
end

class SomeMiddleware < Sidekiq::Middleware::Entry
  def call(job, ctx)
    ctx.logger.info "Executing job #{job.jid}"
    yield
  end
end

MyWorker.async.perform(1_i64)
MyWorker.async.perform(2_i64)

cli = Sidekiq::CLI.new
server = cli.configure do |config|
  config.middleware.add SomeMiddleware.new
  config.redis = ConnectionPool(Redis).new(capacity: 30) do
    Redis.new(host: "localhost", port: 6379)
  end
end
cli.run(server)
