module Sidekiq
  module ExceptionHandler
    abstract class Base
      abstract def call(ex : Exception, ctxHash : Hash(String, JSON::Type)?)
    end
  end

  # The Context interface is passed around by everyone, allowing
  # all code to log, report errors or safely access Redis.
  abstract class Context
    abstract def logger : ::Logger
    abstract def pool : Sidekiq::Pool
    abstract def error_handlers : Array(Sidekiq::ExceptionHandler::Base)
  end
end
