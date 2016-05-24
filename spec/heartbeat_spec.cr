require "./spec_helper"
require "../src/sidekiq/server/heartbeat"

describe Sidekiq::Heartbeat do
  it "beats" do
    svr = Sidekiq::Server.new

    hb = Sidekiq::Heartbeat.new
    j = hb.server_json(svr)
    hostname = `hostname`.strip
    j.should match /#{hostname}/

    hb.❤(svr, j)
  end
end
