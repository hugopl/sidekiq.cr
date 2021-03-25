require "json"
require "./core_ext"

module Sidekiq
  ##
  # The Job class handles the internal business of converting
  # to/from JSON.  In a statically-typed language, this is
  # a bit of a chore.
  class Job
    include JSON::Serializable
    include JSON::Serializable::Unmapped
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

    property queue : String
    property jid : String
    @[JSON::Field(key: "class")]
    property klass : String
    @[JSON::Field(converter: String::RawConverter)]
    property args : String
    @[JSON::Field(converter: Sidekiq::EpochConverter)]
    getter created_at : Time
    @[JSON::Field(converter: Sidekiq::EpochConverter)]
    property at : Time?
    @[JSON::Field(converter: Sidekiq::EpochConverter)]
    property failed_at : Time?
    @[JSON::Field(converter: Sidekiq::EpochConverter)]
    property enqueued_at : Time?
    @[JSON::Field(converter: Sidekiq::EpochConverter)]
    property retried_at : Time?
    property error_class : String?
    property error_message : String?
    property retry_count = 0
    property bid : String?
    property? dead = false
    property error_backtrace : Array(String)?
    property backtrace : (Bool | Int32 | Nil)
    property retry : (Bool | Int32) = false

    @[JSON::Field(ignore: true)]
    @client : Sidekiq::Client?

    def initialize
      @queue = "default"
      @args = "[]"
      @klass = ""
      @created_at = Time.utc
      @jid = Random::Secure.hex(12)
      @retry = true
    end

    def extra_params : Hash(String, JSON::Any)
      json_unmapped
    end

    def extra_params=(value : Hash(String, JSON::Any))
      @json_unmapped = value
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

    def _perform(@args : String)
      client.push(self)
    end

    def _perform_bulk(args : Array(String))
      client.push_bulk(self, args)
    end

    # Run this job at or after the given instant in Time
    def _perform_at(time : Time, @args : String)
      @at = time if time > Time.local
      client.push(self)
    end

    # Run this job +interval+ from now.
    def _perform_in(interval : Time::Span, @args : String)
      now = Time.local
      ts = now + interval
      @at = ts if ts > now

      client.push(self)
    end
  end
end
