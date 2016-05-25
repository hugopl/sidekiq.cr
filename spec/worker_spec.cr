require "./spec_helper"

class MyWorker
  include Sidekiq::Worker

  perform_types Int64, Int64, String

  def perform(a, b, c)
    # puts "hello world!"
  end
end

describe Sidekiq::Worker do
  describe "client-side" do
    it "can create a basic job" do
      jid = MyWorker.async.perform(1_i64, 2_i64, "3")
      jid.should match /[a-f0-9]{24}/
      pool = Sidekiq::Pool.new
      pool.redis { |c| c.lpop("queue:default") }
    end

    it "can schedule a basic job" do
      jid = MyWorker.async.perform_in(60.seconds, 1_i64, 2_i64, "3")
      jid.should match /[a-f0-9]{24}/
    end

    it "can execute a persistent job" do
      jid = MyWorker.async.perform(1_i64, 2_i64, "3")

      pool = Sidekiq::Pool.new

      str = pool.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s)
      job = Sidekiq::Job.new
      job.load(hash.as_h)
      job.execute(MockContext.new)
    end

    it "can persist in bulk" do
      POOL.redis { |c| c.flushdb }
      jids = MyWorker.async.perform_bulk([1_i64, 2_i64, "3"], [1_i64, 2_i64, "4"])
      jids.size.should eq(2)
      jids[0].should_not eq(jids[1])

      pool = Sidekiq::Pool.new

      size = pool.redis { |c| c.llen("queue:default") }
      size.should eq(2)

      str = pool.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s)
      job = Sidekiq::Job.new
      job.load(hash.as_h)
      job.execute(MockContext.new)
    end
  end
end
