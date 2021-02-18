require "log"

module Sidekiq
  class Logger
    # ::Log.define_formatter ::Sidekiq::Logger::PrettyFormat, "#{severity}, [#{timestamp.to_rfc3339} " \
    #                                                         "##{::Process.pid}] -- TID-#{Fiber.current.object_id.to_s(36, io)}" \
    #                                                         ":#{Sidekiq::Logger.context}#{message}"

    # "#{timestamp} #{severity} - #{source(after: ": ")}#{message}" \
    # "#{data(before: " -- ")}#{context(before: " -- ")}#{exception}"

    struct PrettyFormat
      extend ::Log::Formatter

      def self.format(entry : Log::Entry, io : IO)
        label = entry.severity.label
        io << label[0] << ", ["
        entry.timestamp.to_rfc3339(io)
        io << " #" << ::Process.pid << "] "
        label.rjust(7, io)
        io << " -- "

        # io << @progname
        io << "TID-"
        Fiber.current.object_id.to_s(36, io)
        io << ":"

        # io << entry.source << ": "
        io << Sidekiq::Logger.context

        io << entry.message
        if entry.context.size > 0
          io << " -- " << entry.context
        end
        if ex = entry.exception
          io << " -- " << ex.class << ": " << ex
        end
      end
    end

    class PrettyBackend < ::Log::IOBackend
      def initialize(@io = STDOUT)
        super(@io)
        @mutex = Mutex.new(:unchecked)
        @progname = File.basename(PROGRAM_NAME)
        # @formatter = ->formater(::Log::Entry, IO)
        @formatter = PrettyFormat
      end
    end

    def self.context
      c = Fiber.current.sidekiq_logging_context
      c && c.size > 0 ? "#{c.join(' ')}: " : " "
    end

    def self.with_context(msg)
      Fiber.current.sidekiq_logging_context ||= [] of String
      Fiber.current.sidekiq_logging_context.not_nil! << msg
      yield
    ensure
      Fiber.current.sidekiq_logging_context.not_nil!.pop
    end

    def self.build(target, log_target = STDOUT) : ::Log
      name = target.class.name.underscore.gsub("::", ".")
      ::Log.builder.bind(name, :info, Sidekiq::Logger::PrettyBackend.new(log_target))
      ::Log.for(name)
    end
  end
end

class Fiber
  property sidekiq_logging_context : Array(String)?
end
