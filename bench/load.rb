#!/usr/bin/env ruby

# This benchmark is an integration test which creates and
# executes 100,000 no-op jobs through Sidekiq.  This is
# useful for determining job overhead and raw throughput
# on different platforms.
#
# Requirements:
#  - Redis running on localhost:6379
#  - `gem install sidekiq`
#

puts RUBY_DESCRIPTION

require 'sidekiq/cli'
require 'sidekiq/launcher'

include Sidekiq::Util

Sidekiq.configure_server do |config|
  config.redis = { driver: :hiredis, db: 13, port: 6379 }
  config.options[:queues] << 'default'
  config.logger = nil
  config.average_scheduled_poll_interval = 2
end

class LoadWorker
  include Sidekiq::Worker

  def perform(idx)
  end
end

self_read, self_write = IO.pipe
%w(INT TERM).each do |sig|
  begin
    trap sig do
      self_write.puts(sig)
    end
  rescue ArgumentError
    puts "Signal #{sig} not supported"
  end
end

Sidekiq.redis {|c| c.flushdb}
def handle_signal(launcher, sig)
  Sidekiq.logger.debug "Got #{sig} signal"
  case sig
  when 'INT'
    # Handle Ctrl-C in JRuby like MRI
    # http://jira.codehaus.org/browse/JRUBY-4637
    raise Interrupt
  when 'TERM'
    # Heroku sends TERM and then waits 10 seconds for process to exit.
    raise Interrupt
  end
end

def Process.rss
  `ps -o rss= -p #{Process.pid}`.chomp.to_i
end

iter = 10
count = 10_000

iter.times do
  arr = Array.new(count) do
    []
  end
  count.times do |idx|
    arr[idx][0] = idx
  end
  Sidekiq::Client.push_bulk('class' => LoadWorker, 'args' => arr)
end
puts "Created #{count*iter} jobs"

Monitoring = Thread.new do
  watchdog("monitor thread") do
    a = Time.now
    while true
      sleep 0.2
      total = Sidekiq.redis do |conn|
        conn.llen "queue:default"
      end
      puts "RSS: #{Process.rss} Pending: #{total}"
      if total == 0
        b = Time.now
        puts "Done in #{b - a}: #{(iter*count) / (b - a).to_f} jobs/sec"
        exit
      end
    end
  end
end

begin
  fire_event(:startup)
  launcher = Sidekiq::Launcher.new(Sidekiq.options)
  launcher.run

  while readable_io = IO.select([self_read])
    signal = readable_io.first[0].gets.strip
    handle_signal(launcher, signal)
  end
rescue SystemExit => e
rescue => e
  raise e if $DEBUG
  STDERR.puts e.message
  STDERR.puts e.backtrace.join("\n")
  exit 1
end
