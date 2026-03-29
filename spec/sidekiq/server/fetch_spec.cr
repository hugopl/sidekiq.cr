require "../../spec_helper"
require "../../../src/sidekiq/server/fetch"

describe Sidekiq::BasicFetch do
  describe "#bulk_requeue" do
    it "reenqueue jobs" do
      ctx = MockContext.new
      job = Sidekiq::Job.new
      job.queue = "test_requeue"
      unit_of_work = Sidekiq::BasicFetch::UnitOfWork.new("test_requeue", job.to_json, ctx)
      fetcher = Sidekiq::BasicFetch.new ["test_requeue"]
      fetcher.bulk_requeue ctx, [unit_of_work]
      msg = Sidekiq.redis { |c| c.lpop("queue:test_requeue") }
      msg.should eq job.to_json
    end
  end
end
