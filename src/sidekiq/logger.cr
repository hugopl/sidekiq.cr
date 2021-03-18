require "log"

module Sidekiq
  class Logger
    NO_TS = ::Log::Formatter.new do |entry, io|
      io << ::Process.pid
      io << " TID-"
      Fiber.current.object_id.to_s(io, 36)
      entry.data.each do |key, value|
        io << " " << key << "-" << value
      end
      io << " "
      io << entry.severity
      io << ": "
      io << entry.message
    end

    PRETTY = ::Log::Formatter.new do |entry, io|
      io << entry.timestamp.to_utc.to_rfc3339(fraction_digits: 3)
      io << " "
      NO_TS.format(entry, io)
    end

    def self.build(backend : Log::Backend? = nil)
      logger = ::Log.for("Sidekiq", :info)
      logger.backend = if backend
                         backend
                       else
                         formatter = ENV["DYNO"]? ? NO_TS : PRETTY
                         Log::IOBackend.new(formatter: formatter)
                       end
      logger
    end
  end
end
