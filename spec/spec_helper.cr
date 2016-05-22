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
