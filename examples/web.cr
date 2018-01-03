require "../src/sidekiq/web"

# Build this with `crystal compile --release web.cr

Kemal::Session.config do |config|
  # crystal eval 'require "random/secure"; puts Random::Secure.hex(64)'
  config.secret = "3ae480ffc18380c6afa05e96c8a2262c"
end

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
  config.add_handler CSRF.new
end

# The main thing you need to configure with Sidekiq.cr is how to connect to
# Redis. The default is localhost:6379 and typically appropriate for local development.
#
# Redis location should be configured via the REDIS_PROVIDER env variable.
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

Sidekiq::Client.default_context = Sidekiq::Client::Context.new

Kemal.run
