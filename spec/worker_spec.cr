require "./spec_helper"

class MyWorker
  include Sidekiq::Worker
  sidekiq_options do |job|
    job.retry = 5
  end

  def perform(a : Int32, b : Int32, c : String)
  end
end

class Point
  JSON.mapping({x: Float64, y: Float64})
  def initialize(@x, @y)
  end
end

class Circle
  JSON.mapping({radius: Int32, diameter: Int32})
  def initialize(@radius, @diameter)
  end
end

class ComplexWorker
  include Sidekiq::Worker

  def perform(points : Array(Point), circle : Circle)
  end
end

class NoArgumentsWorker
  include Sidekiq::Worker
  sidekiq_options do |job|
    job.retry = 0
  end

  def perform
  end
end

describe Sidekiq::Worker do
  describe "arguments" do
    it "handles arbitrary complexity" do
      p1 = Point.new(1.0, 3.0)
      p2 = Point.new(4.3, 12.5)
      a = [p1, p2]

      ComplexWorker.async.perform(a, Circle.new(9, 17))
      msg = Sidekiq.redis { |c| c.lpop("queue:default") }
      job = Sidekiq::Job.from_json(msg.as(String))
      job.args.should eq("[[{\"x\":1.0,\"y\":3.0},{\"x\":4.3,\"y\":12.5}],{\"radius\":9,\"diameter\":17}]")
      job.execute(MockContext.new)
    end

    it "works without arguments" do
      NoArgumentsWorker.async.perform
      msg = Sidekiq.redis { |c| c.lpop("queue:default") }
      job = Sidekiq::Job.from_json(msg.as(String))
      job.args.should eq("[]")
      job.execute(MockContext.new)
    end
  end

  describe "round-trip" do
    it "coerces types as necessary" do
      jid = MyWorker.async.perform(1, 2, "3")
      msg = Sidekiq.redis { |c| c.lpop("queue:default") }
      job = Sidekiq::Job.from_json(msg.to_s)
      job.execute(MockContext.new)
    end
  end

  describe "server-side" do
    it "can access jid and logger" do
      work = MyWorker.new
      work.jid = "123456789abcdef"
      work.logger.info { "Hello world" }
      work.jid.should eq("123456789abcdef")
      work.bid.should be_nil
    end
  end

  describe "client-side" do
    it "can create a basic job" do
      jid = MyWorker.async {|j| j.queue = "foo" }.perform(1, 2, "3")
      jid.should match /[a-f0-9]{24}/
      job = POOL.redis { |c| c.lpop("queue:foo") }
      job.should_not be_nil
    end

    it "can schedule a basic job" do
      jid = MyWorker.async.perform_in(60.seconds, 1, 2, "3")
      jid.should match /[a-f0-9]{24}/
    end

    it "can execute a persistent job" do
      jid = MyWorker.async.perform(1, 2, "3")
      jid.should_not be_nil


      str = POOL.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s)
      job = Sidekiq::Job.from_json(str.to_s)
      job.execute(MockContext.new)
    end

    it "can create jobs in bulk" do
      count = POOL.redis { |c| c.llen("queue:default") }
      count.should eq(0)
      MyWorker.async.perform_bulk([
        {1, 2, "1"},
        {2, 4, "2"},
        {3, 6, "3"},
        {4, 8, "4"},
      ])
      count = POOL.redis { |c| c.llen("queue:default") }
      count.should eq(4)
    end

    it "can statically and dynamically control job options" do
      job = MyWorker.async
      job.retry.should eq(5)

      j2 = MyWorker.async do |job|
        job.retry = 6
      end
      j2.retry.should eq(6)
    end

  end
end
