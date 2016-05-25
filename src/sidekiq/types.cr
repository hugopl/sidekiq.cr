module Sidekiq
  # Core abstract types used in Sidekiq APIs

  # Only used server-side, any errors experienced within Sidekiq
  # are piped into here.
  module ExceptionHandler
    abstract class Base
      abstract def call(ex : Exception, ctxHash : Hash(String, JSON::Type)?)
    end
  end

  # The Context interface is passed around by everyone, allowing
  # all Sidekiq internals to log, report errors or safely access Redis.
  abstract class Context
    abstract def logger : ::Logger
    abstract def pool : Sidekiq::Pool

    # server-side only, not for use within middleware
    abstract def error_handlers : Array(Sidekiq::ExceptionHandler::Base)
  end
end
