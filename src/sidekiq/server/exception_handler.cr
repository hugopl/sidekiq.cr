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

      def call(ex : Exception, ctxHash : Hash(String, JSON::Type)?)
        @output.warn(ctxHash.to_json) if !ctxHash.empty?
        @output.warn "#{ex.class.name}: #{ex.message}"
        @output.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end

    def handle_exception(server : Sidekiq::Server, ex : Exception, ctxHash : Hash(String, JSON::Type)?)
      server.error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue ex
          puts "!!! ERROR HANDLER THREW AN ERROR !!!"
          puts ex
          puts ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end

  end
end
