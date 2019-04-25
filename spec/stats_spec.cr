require "./spec_helper"
require "../src/sidekiq/api"

describe Sidekiq::Stats do
  describe "History" do
    it "returns proper amount of entries" do
      stats_history = Sidekiq::Stats::History.new(7)
      stats_history.processed.size.should eq(7)
      stats_history.failed.size.should eq(7)

      stats_history = Sidekiq::Stats::History.new(60)
      stats_history.processed.size.should eq(60)
      stats_history.failed.size.should eq(60)
    end

    it "returns correct data from redis" do
      yesterday = (Time.utc.at_beginning_of_day - 1.day).to_s("%Y-%m-%d")
      today = Time.utc.at_beginning_of_day.to_s("%Y-%m-%d")

      Sidekiq.redis do |redis|
        redis.set("stat:failed:#{yesterday}", 42)
        redis.set("stat:processed:#{yesterday}", 120)
      end

      stats_history = Sidekiq::Stats::History.new(2)
      stats_history.processed[yesterday].should eq(120)
      stats_history.failed[yesterday].should eq(42)

      stats_history.processed[today].should eq(0)
      stats_history.failed[today].should eq(0)
    end
  end
end
