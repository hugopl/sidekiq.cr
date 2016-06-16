require "./spec_helper"

class MyWorker
  include Sidekiq::Worker

  def perform(a : Int64, b : Int64, c : String)
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
    end
  end

  describe "round-trip" do
    it "coerces types as necessary" do
      jid = MyWorker.async.perform(1_i64, 2_i64, "3")
      msg = Sidekiq.redis { |c| c.lpop("queue:default") }
      job = Sidekiq::Job.from_json(msg.to_s)
      job.execute(MockContext.new)
    end
  end

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
      jid.should_not be_nil

      pool = Sidekiq::Pool.new

      str = pool.redis { |c| c.lpop("queue:default") }
      hash = JSON.parse(str.to_s)
      job = Sidekiq::Job.from_json(str.to_s)
      job.execute(MockContext.new)
    end

  end
end
