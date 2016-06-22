require "json"
require "logger"
require "../middleware"

module Sidekiq
  module ExceptionHandler
    class Logger < Base
      @output : ::Logger

      def initialize(@output)
      end

      def call(ex : Exception, ctxHash : Hash(String, JSON::Type)? = nil)
        @output.warn(ctxHash.to_json) if ctxHash && !ctxHash.empty?
        @output.warn "#{ex.class.name}: #{ex.message}"
        @output.warn ex.backtrace.join("\n")
      end
    end

    def handle_exception(ctx : Sidekiq::Context, ex : Exception, ctxHash : Hash(String, JSON::Type) = nil)
      ctx.error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue ex2
          ctx.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          ctx.logger.error ex2
          ctx.logger.error ex2.backtrace.join("\n")
        end
      end
    end
  end
end
