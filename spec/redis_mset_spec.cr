require "./spec_helper"
require "../src/sidekiq/api"

# Regression spec for the `mset` bug in the jgaskins/redis shard that kept
# PR #127 in draft.
#
# Up to and including redis v0.14.1, `Redis::Commands#mset` was declared as:
#
#     def mset(data : Hash(String, String))
#
# Because that method lives inside `module Redis::Commands`, the unqualified
# `Hash` resolved to the sibling `Redis::Commands::Hash` command module rather
# than to `::Hash`. Passing a real `::Hash(String, String)` therefore failed to
# compile with:
#
#     Error: Redis::Commands::Hash is not a generic type, it's a module
#
# jgaskins/redis commit eba8014 changed the restriction to `::Hash(String,
# String)`; the fix first shipped in v0.15.0. Sidekiq hits this through
# `Sidekiq::Stats#reset`, which resets counters with a single MSET.
describe "Redis#mset" do
  it "accepts a Hash(String, String)" do
    Sidekiq.redis do |conn|
      conn.mset({"stat:processed" => "5", "stat:failed" => "10"})

      conn.get("stat:processed").should eq("5")
      conn.get("stat:failed").should eq("10")
    end
  end

  it "sets every pair in one command rather than mangling the hash" do
    Sidekiq.redis do |conn|
      conn.mset({"a" => "1", "b" => "2", "c" => "3"})

      conn.get("a").should eq("1")
      conn.get("b").should eq("2")
      conn.get("c").should eq("3")
    end
  end

  it "backs Sidekiq::Stats#reset" do
    Sidekiq.redis do |conn|
      conn.set("stat:processed", "5")
      conn.set("stat:failed", "10")
    end

    Sidekiq::Stats.new.reset

    Sidekiq.redis do |conn|
      conn.get("stat:processed").should eq("0")
      conn.get("stat:failed").should eq("0")
    end
  end
end
