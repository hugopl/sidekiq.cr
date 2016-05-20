require "sidekiq/exception_handler"

module Sidekiq
  ##
  # This module is part of Sidekiq core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60 * 24

    def watchdog(last_words)
      yield
    rescue ex : Exception
      handle_exception(ex, { "context" => last_words })
      raise ex
    end

    def safe_thread(name, &block)
      spawn do
        watchdog(name, &block)
      end
    end

    def hostname
      ENV["DYNO"] || Socket.gethostname
    end

    def process_nonce
      @@process_nonce ||= SecureRandom.hex(6)
    end

    def identity
      @@identity ||= "#{hostname}:#{Process.pid}:#{process_nonce}"
    end

    def fire_event(event, reverse=false)
      arr = Sidekiq.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        begin
          block.call
        rescue ex
          handle_exception(ex, { event: event })
        end
      end
      arr.clear
    end
  end
end
