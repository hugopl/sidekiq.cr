require "json"
require "log"
require "../middleware"

module Sidekiq
  module ExceptionHandler
    class Logger < Base
      @output : ::Log

      def initialize(@output)
      end

      def call(ex : Exception, ctxHash : Hash(String, JSON::Any)? = nil)
        @output.warn { ctxHash.to_json } if ctxHash && !ctxHash.empty?
        @output.warn(exception: ex) { }
      end
    end

    def handle_exception(ctx : Sidekiq::Context, ex : Exception, ctxHash : Hash(String, JSON::Any)? = nil)
      ctx.error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue ex2
          ctx.logger.error(exception: ex2) { "!!! ERROR HANDLER THREW AN ERROR !!!" }
        end
      end
    end
  end
end
