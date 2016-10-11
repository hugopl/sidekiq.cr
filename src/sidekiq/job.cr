require "json"
require "./core_ext"

module Sidekiq

  ##
  # The Job class handles the internal business of converting
  # to/from JSON.  In a statically-typed language, this is
  # a bit of a chore.
  class Job
    #
    # This global registration is a bloody hack.
    # Unclear of a better way of doing it.
    #
    @@jobtypes = Hash(String, -> Sidekiq::Worker).new

    def self.valid?
      @@jobtypes.size > 0
    end

    def self.register(name, klass)
      @@jobtypes[name] = klass
    end

    JSON.mapping({
      queue: String,
      jid: String,
      klass: {type: String, key: "class"},
      args: {type: String, converter: String::RawConverter},
      created_at: {type: Time, converter: Sidekiq::EpochConverter},

      at: {type: Time, converter: Sidekiq::EpochConverter, nilable: true},
      failed_at: {type: Time, converter: Sidekiq::EpochConverter, nilable: true},
      enqueued_at: {type: Time, converter: Sidekiq::EpochConverter, nilable: true},
      retried_at: {type: Time, converter: Sidekiq::EpochConverter, nilable: true},
      error_class: {type: String, nilable: true},
      error_message: {type: String, nilable: true},
      retry_count: {type: Int32, nilable: true},
      bid: {type: String, nilable: true},
      dead: {type: Bool, nilable: true},
      error_backtrace: {type: Array(String), nilable: true},
      backtrace: {type: (Bool | Int32 | Nil), nilable: true},
      retry: {type: (Bool | Int32 | Nil), nilable: true},
    })

    def initialize
      @queue = "default"
      @args = "[]"
      @klass = ""
      @created_at = Time.now.to_utc
      @enqueued_at = nil
      @jid = SecureRandom.hex(12)
      @retry = true
    end

    def client
      @client ||= Sidekiq::Client.new
    end

    def client=(cl : Sidekiq::Client)
      @client = cl
    end

    def execute(ctx : Sidekiq::Context)
      prc = @@jobtypes[klass]?
      raise "No such worker: #{klass}" if prc.nil?

      worker = prc.call
      worker.jid = self.jid
      worker.bid = self.bid
      worker.logger = ctx.logger
      worker._perform(self.args)
      nil
    end

    def _perform(args : String)
      @args = args
      client.push(self)
    end

    def _perform_bulk(args : Array(String))
      client.push_bulk(self, args)
    end

    # Run this job at or after the given instant in Time
    def _perform_at(interval : Time, args : String)
      perform_in(interval.epoch_f, args)
    end

    # Run this job +interval+ from now.
    def _perform_in(interval : Time::Span, args : String)
      now = Time.now
      ts = now + interval

      @args = args
      @at = ts if ts > now

      client.push(self)
    end

  end
end
