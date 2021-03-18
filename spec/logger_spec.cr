require "./spec_helper"
require "../src/sidekiq/logger"

describe Sidekiq::Logger do
  describe "basics" do
    it "logs" do
      backend = Log::MemoryBackend.new
      log = Sidekiq::Logger.build(backend)
      log.info { "test" }
      backend.entries.last.message.should eq("test")
    end
  end
end
