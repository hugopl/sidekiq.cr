require "./spec_helper"
require "../src/sidekiq/logger"
require "log/spec"

describe Sidekiq::Logger do
  describe "basics" do
    it "logs" do
      io = IO::Memory.new
      log = Sidekiq::Logger.build(Sidekiq::Logger, io)
      log.info { "test" }
      io.to_s.should match /INFO -- TID-[\d\w]+: test/
    end

    it "allows multi-level context" do
      io = IO::Memory.new
      log = Sidekiq::Logger.build(Sidekiq::Logger, io)
      Sidekiq::Logger.with_context("one") do
        log.info { "AAA" }
        Sidekiq::Logger.with_context("two") do
          log.info { "BBB" }
        end
        log.info { "CCC" }
      end
      log.info { "DDD" }
      io.to_s.should match /INFO -- TID-[\d\w]+:one: AAA/
      io.to_s.should match /INFO -- TID-[\d\w]+:one two: BBB/
      io.to_s.should match /INFO -- TID-[\d\w]+:one two: BBB/
      io.to_s.should match /INFO -- TID-[\d\w]+:one: CCC/
      io.to_s.should match /INFO -- TID-[\d\w]+: DDD/
    end
  end
end
