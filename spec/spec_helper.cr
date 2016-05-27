require "spec"
require "../src/sidekiq"

POOL = Sidekiq::Pool.new

class MockContext < Sidekiq::Context
  getter pool
  getter logger
  getter output
  getter error_handlers

  def initialize
    @pool = POOL
    @output = MemoryIO.new
    @logger = ::Logger.new(@output)
    @error_handlers = [] of Sidekiq::ExceptionHandler::Base
  end
end

Sidekiq::Client.default_context = MockContext.new

def requires_redis(op, ver, &block)
  redis_version = POOL.redis{|c| c.info["redis_version"] }.as(String)

  proc = if op == :<
    -> { redis_version < ver }
  elsif op == :>=
    -> { redis_version >= ver }
  else
    raise "No such op: #{op}"
  end

  if proc.call
    yield
  else
    pending("These tests require Redis #{op}#{ver}, you are running #{redis_version}", &block)
  end
end
