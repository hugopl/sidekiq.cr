require "./spec_helper"

class SomeMiddleware < Sidekiq::Middleware::ClientEntry
  def call(job, ctx)
    ctx.logger.info "start"
    yield
    ctx.logger.info "done"
    true
  end
end

class StopperMiddleware < Sidekiq::Middleware::ClientEntry
  def call(job, ctx)
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
    ctx.logger.@io.to_s.should match(/start/)
    ctx.logger.@io.to_s.should match(/done/)
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
