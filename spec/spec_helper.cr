require "spec"
require "json_mapping"
require "../src/sidekiq"

POOL = Sidekiq::Pool.new(1)

class MockContext < Sidekiq::Context
  getter pool : Sidekiq::Pool
  getter logger : Log
  getter output
  getter error_handlers : Array(Sidekiq::ExceptionHandler::Base)

  def initialize
    @pool = POOL
    @output = IO::Memory.new
    @error_handlers = [] of Sidekiq::ExceptionHandler::Base
    @logger = Sidekiq::Logger.build(MockContext, @output)
  end
end

Sidekiq::Client.default_context = MockContext.new

def requires_redis(op, ver, &block)
  redis_version = POOL.redis { |c| c.info["redis_version"] }.as(String)

  proc = if op == :<
           ->{ redis_version < ver }
         elsif op == :>=
           ->{ redis_version >= ver }
         else
           raise "No such op: #{op}"
         end

  if proc.call
    yield
  else
    pending("These tests require Redis #{op}#{ver}, you are running #{redis_version}", &block)
  end
end

Spec.before_each do
  Sidekiq.redis { |c| c.flushdb }
end

def refute_match(expected, actual)
  actual.should_not match expected
end

def assert_match(expected, actual)
  actual.should match expected
end

def assert_equal(expected, actual)
  actual.should eq(expected)
end

require "http"

class HTTP::Server::Response
  property! mem : IO::Memory
  property! cresp : HTTP::Client::Response

  def body : String
    output.flush
    output.close
    mem.rewind
    @cresp ||= HTTP::Client::Response.from_io(mem)
    cresp.body.not_nil!
  end
end

def load_fixtures(filename)
  `ruby #{__DIR__}/fixtures/load_fixtures.rb #{__DIR__}/fixtures/#{filename}.marshal.bin`
end
