require "../src/sidekiq/web"

# Build this with `crystal build --release -o kiqweb web.cr

Kemal.config do |config|
  # To enable SSL termination:
  # ./kiqweb --ssl --ssl-key-file your_key_file --ssl-cert-file your_cert_file
  #
  # For more options, including port:
  # ./kiqweb --help
  #
  # Basic authentication:
  #
  # config.add_handler Kemal::Middleware::HTTPBasicAuth.new("username", "password")
end

pool = Sidekiq::Pool.new(
  ConnectionPool(Redis).new(capacity: 30, timeout: 5.0) do
    Redis.new(host: "localhost", port: 6379)
  end
)
Sidekiq::Client.default_context = Sidekiq::Client::Context.new(pool, Sidekiq::Logger.build)

Kemal.run
