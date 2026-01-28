require "json"
require "log"
require "../middleware"

module Sidekiq
  module ExceptionHandler
    class Logger < Base
      def call(ex : Exception, ctx_hash : Hash(String, JSON::Any)? = nil)
        Log.warn(exception: ex) { ctx_hash.try(&.to_json) }
      end
    end

    def handle_exception(ctx : Sidekiq::Context, ex : Exception, ctx_hash : Hash(String, JSON::Any)? = nil)
      ctx.error_handlers.each do |handler|
        begin
          handler.call(ex, ctx_hash)
        rescue e
          Log.error(exception: e) { "!!! ERROR HANDLER THREW AN ERROR !!!" }
        end
      end
    end
  end
end
