require "./exception_handler"

module Sidekiq
  # #
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60 * 24

    def watchdog(ctx, last_words)
      yield
    rescue ex : Exception
      handle_exception(ctx, ex, {"context" => last_words})
      raise ex
    end

    def safe_routine(ctx, name, &block)
      spawn do
        watchdog(ctx, name, &block)
      end
    end

    def fire_event(event, reverse = false)
      arr = Sidekiq.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        begin
          block.call
        rescue ex
          handle_exception(ex, {event: event})
        end
      end
      arr.clear
    end
  end
end
