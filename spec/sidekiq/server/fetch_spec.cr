require "../../spec_helper"
require "../../../src/sidekiq/server/fetch"

describe Sidekiq::BasicFetch do
  describe "#bulk_requeue" do
    it "reenqueue jobs" do
      ctx = MockContext.new
      job = Sidekiq::Job.new
      unit_of_work = Sidekiq::BasicFetch::UnitOfWork.new("default", job.to_json, ctx)
      fetcher = Sidekiq::BasicFetch.new ["default"]
      fetcher.bulk_requeue ctx, [unit_of_work]
      msg = Sidekiq.redis { |c| c.lpop("queue:default") }
      msg.should eq job.to_json
    end
  end
end
