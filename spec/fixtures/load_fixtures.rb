#!/usr/bin/env ruby

require "sidekiq"

filename = ARGV[0]
puts "Loading fixture #{filename}"
hash = File.open(filename, "rb") do |file|
  Marshal.load(file.read)
end

hash.each_pair do |key, value|
  Sidekiq.redis {|c| c.restore(key, 1000, value) }
end
