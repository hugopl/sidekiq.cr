require "./spec_helper"
require "../src/sidekiq/web_helpers"

class ClassWithNumberHelper
  include Sidekiq::WebHelpers
end

class ClassWithPathHelper
  include Sidekiq::WebHelpers
  property request

  def initialize
    @request = HTTP::Request.new(method: "method", resource: "resource")
  end
end

describe Sidekiq::WebHelpers do
  describe "#number_with_delimiter" do
    it "returns formatted number with delimiter" do
      klass = ClassWithNumberHelper.new

      klass.number_with_delimiter(1).should eq "1"
      klass.number_with_delimiter(123).should eq "123"
      klass.number_with_delimiter(1234).should eq "1,234"
      klass.number_with_delimiter(12345).should eq "12,345"
      klass.number_with_delimiter(123456).should eq "123,456"
      klass.number_with_delimiter(1234567).should eq "1,234,567"
      klass.number_with_delimiter(12345678).should eq "12,345,678"
      klass.number_with_delimiter(123456789).should eq "123,456,789"
    end
  end

  describe "#current_path" do
    it "returns current path without parameters" do
      klass = ClassWithPathHelper.new
      klass.request = HTTP::Request.new(method: "GET", resource: "/busy?poll=true")

      klass.current_path.should eq "busy"

      klass.request = HTTP::Request.new(method: "GET", resource: "/?days=90")
      klass.current_path.should eq ""
    end
  end
end
