module Sidekiq
  module EpochConverter
    # https://github.com/crystal-lang/crystal/issues/2643
    def self.to_json(value : Time, io : IO)
      io << value.epoch_f
    end

    def self.from_json(value : JSON::PullParser) : Time
      Time.epoch_ms((value.read_float * 1000).to_i64)
    end
  end
end
