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
end
