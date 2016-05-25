require "logger"

module Sidekiq
  class Logger

    SPACE = " "

    # 2016-05-19T04:19:24.323Z
    PRETTY = Logger::Formatter.new do |severity, time, progname, message, io|
      io.print "#{time.to_utc.to_s("%FT%T.%LZ")} #{::Process.pid} TID-#{Fiber.current.object_id.to_s(36)}#{Sidekiq::Logger.context} #{severity}: #{message}"
    end
    NO_TS = Logger::Formatter.new do |severity, time, progname, message, io|
      io.print "#{::Process.pid} TID-#{Fiber.current.object_id.to_s(36)}#{context} #{severity}: #{message}"
    end

    def self.context
      c = Fiber.current["context"]?
      " #{c.join(SPACE)}" if c && c.size > 0
    end

    def self.with_context(msg)
      Fiber.current["context"] ||= [] of String
      Fiber.current["context"] << msg
      yield
    ensure
      Fiber.current["context"].pop
    end

    def self.build(log_target = STDOUT)
      logger = ::Logger.new(log_target)
      logger.level = Logger::INFO
      logger.formatter = ENV["DYNO"]? ? NO_TS : PRETTY
      logger
    end
  end
end

# UGH, this is hideous but it's the easiest way to get
# fiber-local storage.  Hardcoding the value to Array(String)
# is terrible and needs to be fixed.
class Fiber
  @@fls = Hash(UInt64, Hash(String, Array(String))).new

  def []=(name, value)
    @@fls[self.object_id] ||= Hash(String, Array(String)).new
    @@fls[self.object_id][name] = value
  end
  def [](name)
    @@fls[self.object_id][name]
  end
  def []?(name)
    x = @@fls[self.object_id]?
    return nil unless x
    x[name]?
  end
end
