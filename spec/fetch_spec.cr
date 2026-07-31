require "./spec_helper"
require "../src/sidekiq/server"

describe Sidekiq::BasicFetch do
  ctx = MockContext.new

  it "returns nil when the queues are empty and brpop times out" do
    fetch = Sidekiq::BasicFetch.new(["default"])
    fetch.retrieve_work(ctx).should be_nil
  end

  it "returns a unit of work when a job is queued" do
    POOL.redis(&.rpush("queue:default", "{}"))

    fetch = Sidekiq::BasicFetch.new(["default"])
    uow = fetch.retrieve_work(ctx)
    uow.should_not be_nil
    uow = uow.not_nil!
    uow.job.should eq("{}")
    uow.as(Sidekiq::BasicFetch::UnitOfWork).queue_name.should eq("default")
  end
end
