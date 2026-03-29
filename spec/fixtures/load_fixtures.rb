#!/usr/bin/env ruby

require "redis"

filename = ARGV[0]
puts "Loading fixture #{filename}"
hash = File.open(filename, "rb") do |file|
  Marshal.load(file.read)
end

db = (ENV["SIDEKIQ_TEST_DB"] || 1).to_i
r = Redis.new(db: db)
hash.each_pair do |key, value|
  r.del(key)
  r.restore(key, 1000, value)
end
