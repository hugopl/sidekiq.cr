require "json"
require "./core_ext"

module Sidekiq

  class Job
    #
    # This global registration is a bit of a bloody hack.
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
      args: Array(JSON::Type),
      klass: { key: "class", type: String }
      created_at: {type: Time, converter: EpochConverter},
      enqueued_at: {type: Time, converter: EpochConverter, nilable: true},
      jid: String,
      at: { type: Time, converter: EpochConverter, nilable: true },
      bid: { type: String, nilable: true },
      retry: { type: JSON::Type, nilable: true }, # (Bool, Int64, Nil)
      retry_count: { type: Int64, nilable: true },
      backtrace: { type: JSON::Type, nilable: true }, # (Bool, Int64, Nil)
      dead: { type: Bool, nilable: true },
      failed_at: {type: Time, converter: EpochConverter, nilable: true},
      retried_at: {type: Time, converter: EpochConverter, nilable: true},
      error_class: { type: String, nilable: true },
      error_message: { type: String, nilable: true },
      error_backtrace: { type: Array(String), nilable: true },
    })

    def initialize
      @queue = "default"
      @args = [] of JSON::Type
      @klass = ""
      @created_at = Time.now
      @enqueued_at = nil
      @jid = SecureRandom.hex(12)
      @retry = true
    end

    def load(hash : Hash(String, JSON::Type))
      self.queue = hash["queue"].to_s
      self.klass = hash["class"].to_s
      self.args = hash["args"].as(Array(JSON::Type))
      self.jid = hash["jid"].to_s
      self.bid = hash["bid"]?.try &.to_s
      self.error_class = hash["error_class"]?.try &.to_s
      self.error_message = hash["error_message"]?.try &.to_s
      self.backtrace = hash["backtrace"]?
      self.retry = hash["retry"]?
      self.retry_count = hash["retry_count"]?.try &.as(Int64)
      self.dead = hash["dead"]?.try &.as(Bool)
      if hash["retried_at"]?
        x = hash["retried_at"].as(Float64)
        self.retried_at = Time.epoch_ms((x * 1000).to_i)
      end
      if hash["failed_at"]?
        x = hash["failed_at"].as(Float64)
        self.failed_at = Time.epoch_ms((x * 1000).to_i)
      end
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
      worker._perform(args)
    end

    def perform(*args)
      coer = [] of JSON::Type
      args.each { |x| coer << x.as(JSON::Type) }

      @args = coer
      client.push(self)
    end

    def perform_bulk(*args)
      coer = [] of Array(JSON::Type)
      args.each do |x|
        foo = [] of JSON::Type
        x.each do |arg|
          foo << arg.as(JSON::Type)
        end
        coer << foo
      end
      client.push_bulk(self, coer)
    end

    def perform_bulk(args : Array(Array(JSON::Type)))
      coer = [] of Array(JSON::Type)
      args.each do |x|
        foo = [] of JSON::Type
        x.each do |arg|
          foo << arg.as(JSON::Type)
        end
        coer << foo
      end
      client.push_bulk(self, coer)
    end

    # Run this job at or after the given instant in Time
    def perform_at(interval : Time, *args)
      perform_in(interval.epoch_f, *args)
    end

    # Run this job +interval+ from now.
    def perform_in(interval : Time::Span, *args)
      now = Time.now
      ts = now + interval

      coer = [] of JSON::Type
      args.each { |x| coer << x.as(JSON::Type) }

      @args = coer
      @at = ts if ts > now

      client.push(self)
    end

  end
end
