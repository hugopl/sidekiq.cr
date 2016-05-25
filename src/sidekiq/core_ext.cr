require "big_float"

module Sidekiq
  module EpochConverter
    # https://github.com/crystal-lang/crystal/issues/2643
    def self.to_json(value : Time, io : IO)
      io << BigFloat.new(value.epoch_f).to_s
    end

    def self.from_json(value : JSON::PullParser) : Time
      Time.epoch_ms(value.read_float * 1000)
    end
  end
end

struct Float64
  def to_s
    BigFloat.new(self).to_s
  end

  def to_s(io : IO)
    BigFloat.new(self).to_s(io)
  end
end
