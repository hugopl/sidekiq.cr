module Sidekiq
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
