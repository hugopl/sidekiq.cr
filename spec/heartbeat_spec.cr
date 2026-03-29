require "json"
require "./spec_helper"
require "../src/sidekiq/server/heartbeat"

describe Sidekiq::Heartbeat do
  it "beats" do
    svr = Sidekiq::Server.new

    hb = Sidekiq::Heartbeat.new
    json = hb.server_json(svr)
    ret = JSON.parse json

    ret["hostname"].should eq(System.hostname)

    hb.❤(svr, json)
  end

  it "registers number of busy workers based on Processor's worker_state" do
    svr = Sidekiq::Server.new
    hb = Sidekiq::Heartbeat.new

    json = hb.server_json(svr)

    Sidekiq.redis do |conn|
      hb.❤(svr, json)
      conn.hget(svr.identity, "busy").should eq("0")
    end

    processor = Sidekiq::Processor.new(svr)

    processor.stats(Sidekiq::Job.new) do
      hb.❤(svr, json)
      Sidekiq.redis do |conn|
        conn.hget(svr.identity, "busy").should eq("1")
      end
    end
  end
end
