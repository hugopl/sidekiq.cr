require "./src/sidekiq"
require "./src/sidekiq/server"

# This file is an example of how to start Sidekiq for Crystal.
# You must define one or more Sidekiq::Worker classes
# before you start the server!
class MyWorker
  include Sidekiq::Worker

  perform_types(Int64)
  def perform(x)
    puts "hello!"
  end
end

s = Sidekiq::Server.new
s.start
s.monitor
