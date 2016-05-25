require "./spec_helper"

class SomeMiddleware < Sidekiq::Middleware::Entry
  def call(job, ctx)
    ctx.logger.info "start"
    yield
    ctx.logger.info "done"
  end
end

class MockContext < Sidekiq::Context
  def logger
    @logger ||= ::Logger.new(MemoryIO.new)
  end
end

describe Sidekiq::Middleware do
  describe "client" do
    it "works" do
      ch = Sidekiq::Middleware::Chain.new
      ch.add SomeMiddleware.new

      done = false
      ctx = MockContext.new
      job = Sidekiq::Job.new
      ch.invoke(job, ctx) do
        done = true
      end
    end
  end

  describe "server" do
    it "works" do
    end
  end
end
