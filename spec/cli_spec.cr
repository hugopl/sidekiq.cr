require "./spec_helper"
require "../src/cli"

class FakeWorker
  include Sidekiq::Worker

  def perform
  end
end

describe "Sidekiq::CLI" do
  it "parses" do
    cli = Sidekiq::CLI.new(["-v",
                            "-q", "foo,3",
                            "-q", "xxx",
                            "-c", "50",
                            "-g", "smoky",
                            "-e", "staging",
                            "-t", "9",
    ])
    cli.@concurrency.should eq(50)
    cli.@tag.should eq("smoky")
    cli.@environment.should eq("staging")
    cli.@timeout.should eq(9)
    cli.@queues.should eq(["foo", "foo", "foo", "xxx"])
  end

  it "handles no arguments gracefully" do
    logger = ::Log.for("Sidekiq-test")
    logger.level = :debug

    cli = Sidekiq::CLI.new
    server = cli.create(logger)
    server.queues.should eq(%w(default))
  end
end
