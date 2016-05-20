require "./spec_helper"

class MyWorker
  include Sidekiq::Worker
  extend Sidekiq::Worker::ClassMethods

  def perform(a, b, c)
    puts "hello world!"
  end
end

describe Sidekiq::Worker do
  describe "client-side" do
    it "can create a basic job" do
      jid = MyWorker.async.perform(1, 2, "3")
      jid.should match /[a-f0-9]{24}/
    end
    it "can schedule a basic job" do
      jid = MyWorker.async.perform_in(60_i64, 1, 2, "3")
      jid.should match /[a-f0-9]{24}/
    end

    it "can execute a persistent job" do
      jid = MyWorker.async.perform(1, 2, "3")

      pool = Sidekiq::Pool.new

      str = pool.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s).as_h
      job = Sidekiq::Job.new
      job.queue = hash["queue"].to_s
      job.klass = hash["class"].to_s
      #cargs = [] of JSON::Type
      #hash["args"].to_a.each do |arg|
        #if arg.is_a?(Int)
          #cargs << arg.as_i64
        #elsif arg.is_a?(Float)
          #cargs << arg.as_f64
        #end
      #end
      #job.args = cargs
      job.jid = hash["jid"].to_s
      job.bid = hash["bid"]?.try &.to_s
      job.error_class = hash["error_class"]?.try &.to_s
      job.error_message = hash["error_message"]?.try &.to_s
      job.backtrace = hash["backtrace"]?.try &.to_s
      job.retries = hash["retries"]?
      #job.retry_count = hash["retry_count"]?.try &.to_i
      p job
    end
  end
end
