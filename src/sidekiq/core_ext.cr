struct Time
  # All times are stored in Redis as epoch floats.  The default
  # Float#to_s is terrible for this purpose so we need to roll
  # our own.
  def epoch_s
    "%.6f" % epoch_f
  end
end

module Sidekiq
  module EpochConverter
    def self.to_json(value : Time, io : IO)
      io << "%.6f" % value.epoch_f
    end
    def self.from_json(value : JSON::PullParser) : Time
      Time.epoch_ms(value.read_float * 1000)
    end
  end
end
