#!/usr/bin/env ruby

canretry = true
begin
  require "redis"
rescue
  raise unless canretry
  puts `gem install redis`
  canretry = false
  retry
end

filename = ARGV[0]
puts "Loading fixture #{filename}"
hash = File.open(filename, "rb") do |file|
  Marshal.load(file.read)
end

r = Redis.new
hash.each_pair do |key, value|
  r.restore(key, 1000, value)
end
