require "logger"

module Sidekiq
  class Logger
    @@context = Hash(UInt64, Array(String)).new

    SPACE = " "

    # 2016-05-19T04:19:24.323Z
    PRETTY = Logger::Formatter.new do |severity, time, progname, message, io|
      io.print "#{time.to_utc.to_s("%FT%T.%LZ")} #{::Process.pid} TID-#{Fiber.current.object_id.to_s(36)}#{Sidekiq::Logger.context} #{severity}: #{message}"
    end
    NO_TS = Logger::Formatter.new do |severity, time, progname, message, io|
      io.print "#{::Process.pid} TID-#{Fiber.current.object_id.to_s(36)}#{context} #{severity}: #{message}"
    end

    def self.context
      c = @@context[Fiber.current.object_id]?
      " #{c.join(SPACE)}" if c && c.size > 0
    end

    def self.with_context(msg)
      @@context[Fiber.current.object_id] ||= [] of String
      @@context[Fiber.current.object_id] << msg
      yield
    ensure
      @@context[Fiber.current.object_id].pop
    end

    def self.build(log_target = STDOUT)
      logger = ::Logger.new(log_target)
      logger.level = Logger::INFO
      logger.formatter = ENV["DYNO"]? ? NO_TS : PRETTY
      logger
    end
  end
end
