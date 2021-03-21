require "./spec_helper"

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

class ExtraParamsClientMiddleware < Sidekiq::Middleware::ClientEntry
  @extra_params : Hash(String, JSON::Any)

  def initialize(@extra_params)
  end

  def call(job, ctx) : Bool
    job.extra_params = @extra_params
    yield
    true
  end
end

class ExtraParamsServerMiddleware < Sidekiq::Middleware::ServerEntry
  getter extra_params = Hash(String, JSON::Any).new

  def call(job, ctx) : Bool
    @extra_params = job.extra_params
    yield
    true
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
    ctx.log_entries.first.message.should eq("start")
    ctx.log_entries.last.message.should eq("done")
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

  it "support extra fields injected by middlewares" do
    c = Sidekiq::Client.new
    job = Sidekiq::Job.new
    job.klass = "FakeWorker"
    c.middleware do |chain|
      chain.add(ExtraParamsClientMiddleware.new({"hey" => JSON::Any.new("ho")}))
    end
    x = c.push(job)
    x.should_not be_nil
    server = Sidekiq::Server.new
    server_middleware = ExtraParamsServerMiddleware.new
    server.server_middleware.add(server_middleware)
    processor = Sidekiq::Processor.new(server)
    processor.process_one.should eq(true)
    server_middleware.extra_params.should eq({"hey" => JSON::Any.new("ho")})
  end
end
