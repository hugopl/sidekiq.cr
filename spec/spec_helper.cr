require "spec"
require "../src/sidekiq"

POOL = Sidekiq::Pool.new

class MockContext < Sidekiq::Context
  getter pool
  getter logger
  getter output

  def initialize
    @pool = POOL
    @output = MemoryIO.new
    @logger = ::Logger.new(@output)
  end
end
