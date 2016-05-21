require 'sidekiq'

`redis-cli flushdb`

class LoadWorker
  include Sidekiq::Worker

  def perform(idx)
  end
end

def Process.rss
  `ps -o rss= -p #{Process.pid}`.chomp.to_i
end

iter = 10
count = 10_000

a = Time.now
iter.times do
  args = []
  count.times do |idx|
    args << [idx]
  end
  Sidekiq::Client.push_bulk("class" => LoadWorker, "args" => args)
end
puts "Created #{count*iter} jobs in #{Time.now - a}"
puts Process.rss
