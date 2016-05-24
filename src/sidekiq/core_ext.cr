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
      io << value.epoch_f
    end
    def self.from_json(value : JSON::PullParser) : Time
      Time.epoch_ms(value.read_float * 1000)
    end
  end
end

# https://github.com/crystal-lang/crystal/issues/2643
struct Float64
  def to_s
    String.new(22) do |buffer|
      LibC.snprintf(buffer, 22, "%.8f", self)
      len = LibC.strlen(buffer)
      {len, len}
    end
  end

  def to_s(io : IO)
    chars = StaticArray(UInt8, 22).new(0_u8)
    LibC.snprintf(chars, 22, "%.8f", self)
    io.write_utf8 chars.to_slice[0, LibC.strlen(chars)]
  end
end
