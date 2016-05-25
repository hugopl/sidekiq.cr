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
      c = Fiber.current.logging_context
      " #{c.join(SPACE)}" if c && c.size > 0
    end

    def self.with_context(msg)
      Fiber.current.logging_context ||= [] of String
      Fiber.current.logging_context.not_nil! << msg
      yield
    ensure
      Fiber.current.logging_context.not_nil!.pop
    end

    def self.build(log_target = STDOUT)
      logger = ::Logger.new(log_target)
      logger.level = Logger::INFO
      logger.formatter = ENV["DYNO"]? ? NO_TS : PRETTY
      logger
    end
  end
end

class Fiber
  property logging_context : Array(String)?
end
