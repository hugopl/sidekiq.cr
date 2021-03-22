require "spec"
require "timecop"
require "../src/sidekiq"

Timecop.safe_mode = true

# FIXME: spec/web_spec.cr and spec/scheduled_spec.cr are requiring 2 redis connections.
POOL = Sidekiq::Pool.new(2)

class MockContext < Sidekiq::Context
  getter pool : Sidekiq::Pool
  getter logger : ::Log
  getter error_handlers : Array(Sidekiq::ExceptionHandler::Base)

  def initialize
    @pool = POOL
    @logger = ::Log.for("Sidekiq-test", :debug)
    @logger.backend = ::Log::MemoryBackend.new
    @error_handlers = [] of Sidekiq::ExceptionHandler::Base
  end

  def log_entries
    @logger.backend.as(::Log::MemoryBackend).entries
  end
end

Sidekiq::Client.default_context = MockContext.new

class FakeWorker
  include Sidekiq::Worker

  def perform
  end
end

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
