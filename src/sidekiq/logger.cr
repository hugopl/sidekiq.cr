require "logger"

module Sidekiq
  class Logger
    SPACE = " "

    PRETTY = ::Logger::Formatter.new do |severity, time, progname, message, io|
      # 2016-05-19T04:19:24.323Z
      time.to_utc.to_s("%FT%T.%LZ", io)
      io << " "
      io << ::Process.pid
      io << " TID-"
      Fiber.current.object_id.to_s(36, io)
      io << " "
      io << Sidekiq::Logger.context
      io << " "
      io << severity
      io << ": "
      io << message
    end
    NO_TS = ::Logger::Formatter.new do |severity, time, progname, message, io|
      io << ::Process.pid
      io << " TID-"
      Fiber.current.object_id.to_s(36, io)
      io << " "
      io << Sidekiq::Logger.context
      io << " "
      io << severity
      io << ": "
      io << message
    end

    def self.context
      c = Fiber.current.logging_context
      c && c.size > 0 ? " #{c.join(SPACE)}" : ""
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
      logger.level = ::Logger::INFO
      logger.formatter = ENV["DYNO"]? ? NO_TS : PRETTY
      logger
    end
  end
end

class Fiber
  property logging_context : Array(String)?
end
