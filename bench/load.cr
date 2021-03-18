#!/usr/bin/env -S crystal run --release

require "colorize"
require "redis"
require "../src/sidekiq/server/cli"

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

puts "Compiled with #{{{`crystal -v`.stringify}}}"
puts "Running on #{`uname -a`}"

r = Redis.new
r.flushdb

s = Sidekiq::CLI.new
s.logger.backend = Log::IOBackend.new(File.open(File::NULL, "w"))
x = s.configure do |_config|
  # nothing
end

class LoadWorker
  include Sidekiq::Worker

  def perform(idx : Int64)
  end
end

def Process.rss
  `ps -o rss= -p #{Process.pid}`.chomp.to_i
end

iter = 10
count = 10_000_i64
total = iter * count

a = Time.local
iter.times do
  args = [] of {Int64}
  count.times do |idx|
    args << {idx}
  end
  LoadWorker.async.perform_bulk(args)
end
puts "Created #{count*iter} jobs in #{Time.local - a}"

require "../src/sidekiq/server"

spawn do
  a = Time.local
  loop do
    count = r.llen("queue:default")
    if count == 0
      b = Time.local
      puts "Done in #{b - a}: #{"%.3f" % (total / (b - a).to_f)} jobs/sec".colorize(:green)
      exit
    end
    puts "RSS: #{Process.rss} Pending: #{count}"
    sleep 0.2
  end
end

s.run(x)
