require "secure_random"
require "./util"

module Sidekiq
  class Heartbeat
    include Util

    def initialize
      @daily = Time::Format.new("%Y-%m-%d")
    end

    def start(svr)
      safe_routine(svr, "heartbeat") do
        json = server_json(svr)
        while true
          ❤(svr, json)
          sleep 5
        end
      end
    end

    def clear(svr)
      # Remove record from Redis since we are shutting down.
      # Note we don't stop the heartbeat thread; if the process
      # doesn't actually exit, it"ll reappear in the Web UI.
      id = svr.identity
      svr.pool.redis do |conn|
        conn.pipelined do
          conn.srem("processes", id)
          conn.del("#{id}:workers")
        end
      end
    rescue
      # best effort, ignore network errors
    end

    # private

    def server_json(svr)
      data = {
        "hostname"    => svr.hostname,
        "started_at"  => Time.now.epoch_f,
        "pid"         => ::Process.pid,
        "tag"         => svr.tag,
        "concurrency" => svr.concurrency,
        "queues"      => svr.queues.uniq,
        "labels"      => svr.labels,
        "identity"    => svr.identity,
      }
      # this data doesn"t change so dump it to a string
      # now so we don"t need to dump it every heartbeat.
      data.to_json
    end

    def ❤(svr, json)
      fails = procd = 0
      begin
        procd, fails = Processor.fetch_counts

        workers_key = "#{svr.identity}:workers"
        nowdate = @daily.format(Time.now.to_utc)
        svr.pool.redis do |conn|
          conn.multi do |multi|
            multi.incrby("stat:processed", procd)
            multi.incrby("stat:processed:#{nowdate}", procd)
            multi.incrby("stat:failed", fails)
            multi.incrby("stat:failed:#{nowdate}", fails)
            multi.del(workers_key)
            Processor.worker_state.each do |tid, hash|
              multi.hset(workers_key, tid, hash.to_json)
            end
            multi.expire(workers_key, 60)
          end
        end
        fails = procd = 0

        _, _, _, msg = svr.pool.redis do |conn|
          conn.multi do |multi|
            multi.sadd("processes", svr.identity)
            multi.hmset(svr.identity, {"info"  => json,
              "busy"  => svr.busy,
              "beat"  => Time.now.epoch_f,
              "quiet" => svr.stopping?})
            multi.expire(svr.identity, 60)
            multi.rpop("#{svr.identity}-signals")
          end
        end.as(Array)
        msgs = msg.as(String?)

        return unless msgs

        ::Process.kill(Signal.parse(msgs), ::Process.pid)
      rescue e
        # ignore all redis/network issues
        svr.logger.error("heartbeat: #{e.message}")
        # don"t lose the counts if there was a network issue
        Processor.reset_counts(procd, fails)
      end
    end
  end
end
