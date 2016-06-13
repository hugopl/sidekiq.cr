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
  property! mem : MemoryIO
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
