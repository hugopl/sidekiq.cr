require "json"

class Sidekiq
  class Job
    @@jobtypes = Hash(String, Sidekiq::Worker).new

    def self.register(klass)
      @@jobtypes[klass.name] = klass
    end

    JSON.mapping({
      queue: String,
      args: Array(JSON::Type),
      klass: { key: "class", type: String }
      created_at: Float64,
      enqueued_at: Float64,
      jid: String,
      at: { type: Int64, nilable: true },
      bid: { type: String, nilable: true },
      retries: { type: JSON::Type, nilable: true },
      retry_count: { type: Int64, nilable: true },
      backtrace: { type: JSON::Type, nilable: true },
      failed_at: { type: Float64, nilable: true },
      error_class: { type: String, nilable: true },
      error_message: { type: String, nilable: true },
      error_backtrace: { type: Array(String), nilable: true },
    })

    def initialize
      @queue = "default"
      @args = [] of JSON::Type
      @klass = ""
      @created_at = Time.now.epoch_f
      @enqueued_at = 0.0
      @jid = SecureRandom.hex(12)
    end

    def client
      @client ||= Sidekiq::Client.new(Sidekiq::Pool.new)
    end

    def client=(cl : Sidekiq::Client)
      @client = cl
    end

    def created
      Time.epoch_ms((created_at * 1000).to_i)
    end

    def enqueued
      Time.epoch_ms((enqueued_at * 1000).to_i)
    end

    def execute
      worker = @@jobtypes[klass].new
      worker.jid = jid
      worker.bid = bid
      worker.perform(*args)
    end

    def perform(*args)
      coer = [] of JSON::Type
      args.each { |x| coer << coerce(x) }

      @args = coer
      client.push(self)
    end

    def coerce(arg : Int32) : JSON::Type
      val = 0_i64
      val += arg
      val
    end

    def coerce(arg : Float32) : JSON::Type
      val = 0_f64
      val += arg
      val
    end

    def coerce(arg : JSON::Type) : JSON::Type
      arg
    end

    def perform_bulk(args : Array(Array(JSON::Any)))
      client.push_bulk(self, args)
    end

    # Run this job at or after the given instant in Time
    def perform_at(interval : Time, *args)
      perform_in(interval.epoch_f, *args)
    end

    # Run this job +interval+ seconds from now.
    def perform_in(interval : Int64, *args)
      now = Time.now
      ts = (interval < 1_000_000_000 ? (now.epoch + interval) : interval)

      coer = [] of JSON::Type
      args.each { |x| coer << coerce(x) }
      @args = coer
      @at = ts if ts > now.epoch_f

      client.push(self)
    end

  end
end
