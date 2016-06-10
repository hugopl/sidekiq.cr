#!/usr/bin/env ruby

if File.exist?("ruby_compat.marshal.bin")
  puts "File exists, nothing to do"
  exit
end

require "sidekiq"
require "sidekiq/api"

Sidekiq.logger.level = Logger::DEBUG

raise "DeadSet is not empty!" unless Sidekiq::DeadSet.new.size == 0
raise "RetrySet is not empty!" unless Sidekiq::RetrySet.new.size == 0

class RubyWorker
  include Sidekiq::Worker
  sidekiq_options retry: 4
  def perform(int, float, str, bool)
  end
end

3.times do |idx|
  RubyWorker.set(queue: "foo").perform_async(idx, 0.5, "mike", idx.odd?)
end

5.times do |idx|
  RubyWorker.set(retry: 0).perform_async(idx, 0.5, "mike", idx.odd?)
  #Sidekiq::Client.push("queue" => "default", "retry" => nil, "class" => "RubyWorker", "args" => [idx, 0.5, "mike", idx.odd?])
end

4.times do |idx|
  RubyWorker.perform_in(10, idx, 0.5, "mike", idx.odd?)
end

require "sidekiq/middleware/server/retry_jobs"

# this should create a Dead job exactly how Ruby does it.
msg = Sidekiq.redis{|c| c.lpop("queue:default") }
job = JSON.parse(msg)
mid = Sidekiq::Middleware::Server::RetryJobs.new
begin
  mid.call(RubyWorker.new, job, "default") do
    raise "boom"
  end
rescue RuntimeError
end

raise "DeadSet should have a job now!" unless Sidekiq::DeadSet.new.size == 1

# this should create a Retry exactly how Ruby does it.
msg = Sidekiq.redis{|c| c.lpop("queue:foo") }
job = JSON.parse(msg)
mid = Sidekiq::Middleware::Server::RetryJobs.new
begin
  mid.call(RubyWorker.new, job, "foo") do
    raise "boom"
  end
rescue RuntimeError
end

raise "DeadSet should have a job now!" unless Sidekiq::DeadSet.new.size == 1
raise "Unexpected default queue size" unless Sidekiq::Queue.new.size == 4
raise "Unexpected foo queue size" unless Sidekiq::Queue.new("foo").size == 2

KEYS = %w(queue:default queue:foo retry schedule dead)
hash = KEYS.inject({}) {|memo, name| data = Sidekiq.redis{|c| c.dump(name)}; memo[name] = data; memo }

File.open("ruby_compat.marshal.bin", "wb") do |file|
  file.write(Marshal.dump(hash))
end
