require "json"
require "logger"

module Sidekiq
  module ExceptionHandler
    abstract class Base
      abstract def call(ex : Exception, ctxHash : Hash(String, JSON::Type)?)
    end

    class Logger < Base
      @output : ::Logger

      def initialize(@output)
      end

      def call(ex : Exception, ctxHash : Hash(String, JSON::Type)? = nil)
        @output.warn(ctxHash.to_json) if !ctxHash.empty?
        @output.warn "#{ex.class.name}: #{ex.message}"
        @output.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end

    def handle_exception(ctx : Sidekiq::Context, ex : Exception, ctxHash : Hash(String, JSON::Type)?)
      ctx.error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue ex
          ctx.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          ctx.logger.error ex
          ctx.logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end

  end
end
