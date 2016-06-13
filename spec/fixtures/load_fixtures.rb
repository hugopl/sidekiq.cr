#!/usr/bin/env ruby

require "redis"

filename = ARGV[0]
puts "Loading fixture #{filename}"
hash = File.open(filename, "rb") do |file|
  Marshal.load(file.read)
end

r = Redis.new
hash.each_pair do |key, value|
  r.restore(key, 1000, value)
end
