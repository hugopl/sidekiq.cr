module Sidekiq
  class Heartbeat
    PROCTITLES = [
      ->(svr) { "sidekiq #{Sidekiq::VERSION}" },
      ->(svr) { @svr.tag },
      ->(svr) { "[#{svr.busy} of #{svr.concurrency} busy]" },
      ->(svr){ "stopping" if svr.stopping? },
    ]

    getter logger : ::Logger

    def initialize(@svr)
      @svr = svr
      @logger = svr.logger
    end

    def heartbeat(k, data, json)
      results = PROCTITLES.map {|x| x.call(@svr) }
      results.compact!
      results.join(" ")

      ❤(k, json)
    end

    def ❤(key, json)
      fails = procd = 0
      begin
        fails = 0
        procd = 0

        workers_key = "#{key}:workers"
        nowdate = Time.now.utc.strftime("%Y-%m-%d")
        @svr.pool.redis do |conn|
          conn.multi do
            conn.incrby("stat:processed", procd)
            conn.incrby("stat:processed:#{nowdate}", procd)
            conn.incrby("stat:failed", fails)
            conn.incrby("stat:failed:#{nowdate}", fails)
            conn.del(workers_key)
            Processor::WORKER_STATE.each_pair do |tid, hash|
              conn.hset(workers_key, tid, hash.to_json)
            end
            conn.expire(workers_key, 60)
          end
        end
        fails = procd = 0

        _, _, _, msg = @svr.pool.redis do |conn|
          conn.multi do
            conn.sadd("processes", key)
            conn.hmset(key, "info", json, "busy", @svr.busy, "beat", Time.now.epoch_s, "quiet", @svr.stopping?)
            conn.expire(key, 60)
            conn.rpop("#{key}-signals")
          end
        end

        return unless msg

        ::Process.kill(msg, Process.pid)
      rescue e
        # ignore all redis/network issues
        logger.error("heartbeat: #{e.message}")
        # don"t lose the counts if there was a network issue
        Processor::PROCESSED.increment(procd)
        Processor::FAILURE.increment(fails)
      end
    end

    def start_heartbeat
      k = identity
      data = {
        "hostname" => hostname,
        "started_at" => Time.now.epoch_s,
        "pid" => Process.pid,
        "tag" => @svr.tag,
        "concurrency" => @svr.concurrency,
        "queues" => @svr.queues.uniq,
        "labels" => @svr.labels,
        "identity" => k,
      }
      # this data doesn"t change so dump it to a string
      # now so we don"t need to dump it every heartbeat.
      json = data.to_json

      while true
        heartbeat(k, data, json)
        sleep 5
      end
      logger.info("Heartbeat stopping...")
    end

    def clear_heartbeat
      # Remove record from Redis since we are shutting down.
      # Note we don"t stop the heartbeat thread; if the process
      # doesn"t actually exit, it"ll reappear in the Web UI.
      @svr.pool.redis do |conn|
        conn.pipelined do
          conn.srem("processes", identity)
          conn.del("#{identity}:workers")
        end
      end
    rescue
      # best effort, ignore network errors
    end

  end
end

