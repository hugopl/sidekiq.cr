require "json"
require "log"
require "../middleware"

module Sidekiq
  module ExceptionHandler
    class Logger < Base
      @output : ::Log

      def initialize(@output)
      end

      def call(ex : Exception, ctx : Hash(String, JSON::Any)? = nil)
        @output.warn(exception: ex) { ctx.try(&.to_json) }
      end
    end

    def handle_exception(ctx : Sidekiq::Context, ex : Exception, ctx_hash : Hash(String, JSON::Any)? = nil)
      ctx.error_handlers.each do |handler|
        begin
          handler.call(ex, ctx_hash)
        rescue e
          ctx.logger.error(exception: e) { "!!! ERROR HANDLER THREW AN ERROR !!!" }
        end
      end
    end
  end
end
