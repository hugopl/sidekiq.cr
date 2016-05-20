require "./spec_helper"

class SomeMiddleware < Sidekiq::Middleware::Client
  def call(job)
    p job
    yield
  end
end

describe Sidekiq::Middleware do
  it "accepts entries" do
    ch = Sidekiq::Middleware::Chain.new
    ch.add SomeMiddleware.new
    ch.entries.size.should eq(1)
  end
end
