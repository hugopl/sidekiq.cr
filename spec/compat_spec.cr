require "./spec_helper"

describe "ruby compatibility" do
  describe "API" do
    requires_redis(:>=, "3.2") do
      it "works with Ruby-based retries" do
        load_fixtures("ruby_compat")

        rs = Sidekiq::RetrySet.new
        rs.size.should eq(1)
        rs.each do |retri|
          retri.queue.should eq("foo")
          retri.at.should be < Time.local
        end
      end
    end
  end
end
