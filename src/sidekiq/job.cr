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

    property! queue : String
    property! jid : String
    property! klass : String
    property! args : Array(JSON::Type)
    property! created_at : Time

    property bid : String?
    property at : Time?
    property failed_at : Time?
    property retried_at : Time?
    property enqueued_at : Time?
    property retry_count : Int64?
    property error_class : String?
    property error_message : String?
    property error_backtrace : Array(String)?
    property dead : Bool?
    property backtrace : (Bool | Int64 | Nil)
    property retry : (Bool | Int64 | Nil)

    def to_h : Hash(String, JSON::Type)
      h = Hash(String, JSON::Type).new
      h["jid"] = jid
      h["args"] = args
      h["queue"] = queue
      h["class"] = klass
      h["created_at"] = created_at.epoch_f

      h["bid"] = bid if bid
      h["at"] = at.not_nil!.epoch_f if at
      h["failed_at"] = failed_at.not_nil!.epoch_f if failed_at
      h["retried_at"] = retried_at.not_nil!.epoch_f if retried_at
      h["enqueued_at"] = enqueued_at.not_nil!.epoch_f if enqueued_at
      h["retry_count"] = retry_count if retry_count
      h["dead"] = dead if dead
      h["backtrace"] = backtrace if backtrace
      h["retry"] = retry if retry
      h["error_class"] = error_class if error_class
      h["error_message"] = error_message if error_message
      h["error_backtrace"] = error_backtrace.not_nil!.map{|x| x.as(JSON::Type)} if error_backtrace
      h
    end

    def to_json : String
      to_h.to_json
    end

    def initialize
      @queue = "default"
      @args = [] of JSON::Type
      @klass = ""
      @created_at = Time.now.to_utc
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

      x = hash["backtrace"]?
      if x && x.is_a?(Int64)
        self.backtrace = x.as(Int64)
      elsif x && x.is_a?(Bool)
        self.backtrace = x.as(Bool)
      elsif x
        raise "Invalid 'backtrace' value: #{x.inspect} / #{x.class.name}"
      else
        self.backtrace = nil
      end

      x = hash["retry"]?
      if x && x.is_a?(Int64)
        self.retry = x.as(Int64)
      elsif x && x.is_a?(Bool)
        self.retry = x.as(Bool)
      elsif x
        raise "Invalid 'retry' value: #{x.inspect} / #{x.class.name}"
      else
        self.retry = nil
      end

      self.retry_count = hash["retry_count"]?.try &.as(Int64)
      self.dead = hash["dead"]?.try &.as(Bool)
      if hash["at"]?
        x = hash["at"].as(Float64)
        self.at = Time.epoch_ms((x * 1000).to_i64)
      end
      if hash["enqueued_at"]?
        x = hash["enqueued_at"].as(Float64)
        self.enqueued_at = Time.epoch_ms((x * 1000).to_i64)
      end
      if hash["created_at"]?
        x = hash["created_at"].as(Float64)
        self.created_at = Time.epoch_ms((x * 1000).to_i64)
      end
      if hash["retried_at"]?
        x = hash["retried_at"].as(Float64)
        self.retried_at = Time.epoch_ms((x * 1000).to_i64)
      end
      if hash["failed_at"]?
        x = hash["failed_at"].as(Float64)
        self.failed_at = Time.epoch_ms((x * 1000).to_i64)
      end

      x = hash["error_backtrace"]?
      if x && x.is_a?(Array)
        self.error_backtrace = x.as(Array).map{|y| y.as(String) }
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

    def _perform(*args)
      coer = [] of JSON::Type
      args.each { |x| coer << x.as(JSON::Type) }

      @args = coer
      client.push(self)
    end

    def _perform_bulk(*args)
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

    def _perform_bulk(args : Array(Array(JSON::Type)))
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
    def _perform_at(interval : Time, *args)
      perform_in(interval.epoch_f, *args)
    end

    # Run this job +interval+ from now.
    def _perform_in(interval : Time::Span, *args)
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
