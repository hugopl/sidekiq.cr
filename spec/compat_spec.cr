require "./spec_helper"

describe "ruby compatibility" do
  describe "API" do
    if File.exists?("#{__DIR__}/fixtures/ruby_compat.marshal.bin")
      it "works with Ruby-based retries" do
        load_fixtures("ruby_compat")

        rs = Sidekiq::RetrySet.new
        rs.size.should eq(1)
        rs.each do |retri|
          retri.queue.should eq("foo")
          retri.at.should be < Time.now
        end
      end
    else
      puts "No fixture file found, run \"make fixtures\" to generate"
    end
  end
end


