require "./src/sidekiq/web"

pool = Sidekiq::Pool.new(
  ConnectionPool(Redis).new(capacity: 30, timeout: 5.0) do
    Redis.new(host: "localhost", port: 6379)
  end
)
Sidekiq::Client.default_context = Sidekiq::Client::Context.new(pool, Sidekiq::Logger.build)

Kemal.run
