require "./src/sidekiq"

`redis-cli flushdb`

class LoadWorker
  include Sidekiq::Worker

  perform_types Int64
  def perform(idx)
  end
end

def Process.rss
  `ps -o rss= -p #{Process.pid}`.chomp.to_i
end

iter = 10
count = 10_000_i64

a = Time.now
iter.times do
  args = [] of Array(Int64)
  count.times do |idx|
    args << [idx]
  end
  LoadWorker.async.perform_bulk(args)
end
puts "Created #{count*iter} jobs in #{Time.now - a}"
puts Process.rss

require "./src/sidekiq/server"

spawn do
  loop do
    r = Redis.new
    count = r.llen("queue:default")
    p [Time.now, count, Process.rss]
    sleep 1
  end
end

s = Sidekiq::Server.new(concurrency: 100, logger: Logger.new(File.open("something.txt", "w")))
s.start
s.monitor
