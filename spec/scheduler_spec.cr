require "./spec_helper"
require "../src/sidekiq/server/scheduled"

describe "scheduler" do
  it "polls" do
    p = Sidekiq::Scheduled::Poller.new(MockContext.new)
    p.enqueue
  end
end
