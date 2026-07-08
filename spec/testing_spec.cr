require "./spec_helper"
require "../src/sidekiq/testing"

class TestingWorker
  include Sidekiq::Worker

  @@performed = [] of String

  def self.performed
    @@performed
  end

  def self.reset
    @@performed = [] of String
  end

  def perform(msg : String)
    @@performed << msg
  end
end

Spec.after_each do
  Sidekiq.test_mode = :disable
  TestingWorker.reset
end

describe "Sidekiq.testing" do
  it "defaults to Disable, i.e. normal behavior, pushing to Redis" do
    Sidekiq.test_mode.should eq(Sidekiq::TestMode::Disable)

    TestingWorker.async.perform("hello")

    TestingWorker.performed.should be_empty
    POOL.redis(&.llen("queue:default")).should eq(1)
  end

  it "runs jobs inline instead of pushing to Redis when set to Inline" do
    Sidekiq.testing(Sidekiq::TestMode::Inline)

    TestingWorker.async.perform("hello")

    TestingWorker.performed.should eq(["hello"])
    POOL.redis(&.llen("queue:default")).should eq(0)
  end

  it "runs bulk jobs inline instead of pushing to Redis when set to Inline" do
    Sidekiq.testing(Sidekiq::TestMode::Inline)

    TestingWorker.async.perform_bulk([{"a"}, {"b"}, {"c"}])

    TestingWorker.performed.should eq(["a", "b", "c"])
    POOL.redis(&.llen("queue:default")).should eq(0)
  end

  it "runs the block in Inline mode and restores the previous mode afterwards" do
    Sidekiq.testing(Sidekiq::TestMode::Inline) do
      Sidekiq.test_mode.should eq(Sidekiq::TestMode::Inline)
      TestingWorker.async.perform("block")
    end

    Sidekiq.test_mode.should eq(Sidekiq::TestMode::Disable)
    TestingWorker.performed.should eq(["block"])
  end

  it "restores a previously active (non-default) mode after the block form returns" do
    Sidekiq.testing(Sidekiq::TestMode::Inline)

    Sidekiq.testing(Sidekiq::TestMode::Disable) do
      TestingWorker.async.perform("nested")
    end

    Sidekiq.test_mode.should eq(Sidekiq::TestMode::Inline)
    TestingWorker.performed.should be_empty
    POOL.redis(&.llen("queue:default")).should eq(1)
  end

  it "raises when a scheduled job (perform_at/perform_in) is pushed in Inline mode" do
    Sidekiq.testing(Sidekiq::TestMode::Inline)

    expect_raises(Exception, /does not make sense with perform_at\/perform_in/) do
      TestingWorker.async.perform_in(1.hour, "later")
    end

    TestingWorker.performed.should be_empty
  end
end
