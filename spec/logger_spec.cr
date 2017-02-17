require "./spec_helper"
require "../src/sidekiq/logger"

describe Sidekiq::Logger do
  describe "basics" do
    it "logs" do
      io = IO::Memory.new
      log = Sidekiq::Logger.build(io)
      log.info "test"
      io.to_s.should match /INFO: test/
    end

    it "allows multi-level context" do
      io = IO::Memory.new
      log = Sidekiq::Logger.build(io)
      Sidekiq::Logger.with_context("one") do
        log.info "AAA"
        Sidekiq::Logger.with_context("two") do
          log.info "BBB"
        end
        log.info "CCC"
      end
      log.info "DDD"
      io.to_s.should match /one INFO: AAA/
      io.to_s.should match /one two INFO: BBB/
      io.to_s.should match /one INFO: CCC/
      io.to_s.should match /INFO: DDD/
    end
  end
end
