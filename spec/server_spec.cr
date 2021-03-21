require "./spec_helper"
require "../src/sidekiq/server"

class Foo < Sidekiq::Middleware::ServerEntry
  def call(job, ctx) : Bool
    yield
  end
end

describe "Sidekiq::Server" do
  it "allows adding middleware" do
    s = Sidekiq::Server.new
    s.server_middleware.add Foo.new
    s.server_middleware.entries.size.should eq(3)
  end

  it "allows removing middleware" do
    s = Sidekiq::Server.new
    s.server_middleware.entries.size.should eq(2)
    s.server_middleware.entries[0].should be_a(Sidekiq::Middleware::Logger)
    s.server_middleware.remove(Sidekiq::Middleware::Logger)
    s.server_middleware.entries.size.should eq(1)
    s.server_middleware.entries[0].should be_a(Sidekiq::Middleware::RetryJobs)
  end

  it "will stop" do
    s = Sidekiq::Server.new
    s.stopping?.should be_false
    s.request_stop
    s.stopping?.should be_true
  end

  it "maintains the processor list" do
    s = Sidekiq::Server.new
    s.processors.size.should eq(0)
    p = s.processor_died(nil, nil)
    s.processors.size.should eq(1)
    s.processor_stopped(nil)
    s.processors.size.should eq(1)
    r = s.processor_died(p, nil)
    r.should_not be_nil
    s.processors.size.should eq(1)
    s.request_stop
    t = s.processor_died(r, nil)
    t.should be_nil
    s.processors.size.should eq(0)
  end
end
