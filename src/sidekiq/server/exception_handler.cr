require "json"
require "logger"

module Sidekiq
  module ExceptionHandler
    class Logger
      @output : ::Logger

      def initialize(@output)
      end

      def call(ex : Exception, ctxHash : Hash(String, JSON::Any)?)
        @output.warn(JSON.dump(ctxHash)) if !ctxHash.empty?
        @output.warn "#{ex.class.name}: #{ex.message}"
        @output.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end

    def handle_exception(ex : Exception, ctxHash : Hash(String, JSON::Any)?)
      error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue ex
          logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          logger.error ex
          logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end

  end
end
