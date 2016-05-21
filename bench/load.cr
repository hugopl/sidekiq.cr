#!/usr/bin/env crystal

require "../src/sidekiq"

# This benchmark is an integration test which creates and
# executes 100,000 no-op jobs through Sidekiq.  This is
# useful for determining job overhead and raw throughput
# on different platforms.
#
# Requirements:
#  - Redis running on localhost:6379
#  - `crystal deps`
#  - `crystal run --release bench/load.cr
#


r = Redis.new
r.flushdb

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

require "../src/sidekiq/server"
a = Time.now

spawn do
  loop do
    count = r.llen("queue:default")
    if count == 0
      puts "Done in #{Time.now - a}"
      exit
    end
    p [Time.now, count, Process.rss]
    sleep 1
  end
end

s = Sidekiq::Server.new(concurrency: 25, logger: Logger.new(File.open("something.txt", "w")))
s.start
s.monitor
