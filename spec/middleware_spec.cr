require "./spec_helper"
require "log/spec"

class SomeMiddleware < Sidekiq::Middleware::ClientEntry
  def call(job, ctx) : Bool
    ctx.logger.info { "start" }
    yield
    ctx.logger.info { "done" }
    true
  end
end

class StopperMiddleware < Sidekiq::Middleware::ClientEntry
  def call(job, ctx) : Bool
    if false
      yield
    else
      false
    end
  end
end

describe Sidekiq::Middleware do
  it "allows middleware to stop a push" do
    ch = Sidekiq::Middleware::Chain(Sidekiq::Middleware::ClientEntry).new
    ch.add StopperMiddleware.new

    done = false
    ctx = MockContext.new
    job = Sidekiq::Job.new
    result = ch.invoke(job, ctx) do
      done = true
    end

    done.should be_false
    result.should be_false
  end

  it "works" do
    ::Log.capture do |logs|
      ch = Sidekiq::Middleware::Chain(Sidekiq::Middleware::ClientEntry).new
      ch.add SomeMiddleware.new

      done = false
      ctx = MockContext.new
      job = Sidekiq::Job.new
      result = ch.invoke(job, ctx) do
        done = true
      end
      done.should be_true
      result.should be_true

      logs.check(:info, /start/i)
      logs.check(:info, /done/i)
    end
  end

  it "can stop a client-side push" do
    c = Sidekiq::Client.new
    job = Sidekiq::Job.new
    x = c.push(job)
    x.should_not be_nil

    c.middleware do |chain|
      chain.add StopperMiddleware.new
    end

    job = Sidekiq::Job.new
    x = c.push(job)
    x.should be_nil
  end
end
