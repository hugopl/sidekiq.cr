require "./spec_helper"

class MyWorker
  include Sidekiq::Worker

  sidekiq_perform Int64, Int64, String

  def perform(a, b, c)
    puts "hello world!"
  end
end

describe Sidekiq::Worker do
  describe "client-side" do
    it "can create a basic job" do
      jid = MyWorker.async.perform(1_i64, 2_i64, "3")
      jid.should match /[a-f0-9]{24}/
    end

    it "can schedule a basic job" do
      jid = MyWorker.async.perform_in(60_i64, 1_i64, 2_i64, "3")
      jid.should match /[a-f0-9]{24}/
    end

    it "can execute a persistent job" do
      jid = MyWorker.async.perform(1_i64, 2_i64, "3")

      pool = Sidekiq::Pool.new

      str = pool.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s)
      job = Sidekiq::Job.new
      job.load(hash.as_h)
      job.execute()
      p job
    end
  end
end
