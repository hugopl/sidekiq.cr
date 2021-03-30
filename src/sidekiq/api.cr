require "./job"

module Sidekiq
  class Stats
    @stats : Hash(String, JSON::Any)

    def initialize
      @stats = fetch_stats!
    end

    def processed
      stat "processed"
    end

    def failed
      stat "failed"
    end

    def scheduled_size
      stat "scheduled_size"
    end

    def retry_size
      stat "retry_size"
    end

    def dead_size
      stat "dead_size"
    end

    def enqueued
      stat "enqueued"
    end

    def processes_size
      stat "processes_size"
    end

    def workers_size
      stat "workers_size"
    end

    def default_queue_latency
      stat "default_queue_latency"
    end

    def queues
      Sidekiq::Stats::Queues.new.lengths
    end

    def fetch_stats!
      pipe1_res = Sidekiq.redis do |conn|
        conn.pipelined do |ppp|
          ppp.get("stat:processed")
          ppp.get("stat:failed")
          ppp.zcard("schedule")
          ppp.zcard("retry")
          ppp.zcard("dead")
          ppp.scard("processes")
          ppp.lrange("queue:default", -1, -1)
          ppp.smembers("processes")
          ppp.smembers("queues")
        end
      end.as(Array(Redis::RedisValue))

      procs = pipe1_res[7].as(Array(Redis::RedisValue))
      qs = pipe1_res[8].as(Array(Redis::RedisValue))

      pipe2_res = Sidekiq.redis do |conn|
        conn.pipelined do |ppp|
          procs.each { |key| ppp.hget(key.to_s, "busy") }
          qs.each { |queue| ppp.llen("queue:#{queue}") }
        end
      end.as(Array(Redis::RedisValue))

      sizes = pipe2_res.map { |x| x ? x.to_s.to_i : 0 }

      s = procs.size
      workers_size = sizes[0...s].sum
      enqueued = sizes[s..-1].sum

      default_queue_latency = if (entry = pipe1_res[6].as(Array(Redis::RedisValue)).first?)
                                hash = JSON.parse(entry.as(String))
                                was = hash["enqueued_at"].as_f
                                Time.local.to_unix_f - was
                              else
                                0.0_f64
                              end
      Hash(String, JSON::Any){
        "processed"      => JSON::Any.new(pipe1_res[0] ? pipe1_res[0].as(String).to_i64 { 0_i64 } : 0_i64),
        "failed"         => JSON::Any.new(pipe1_res[1] ? pipe1_res[1].as(String).to_i64 { 0_i64 } : 0_i64),
        "scheduled_size" => JSON::Any.new(pipe1_res[2].as(Int64)),
        "retry_size"     => JSON::Any.new(pipe1_res[3].as(Int64)),
        "dead_size"      => JSON::Any.new(pipe1_res[4].as(Int64)),
        "processes_size" => JSON::Any.new(pipe1_res[5].as(Int64)),

        "default_queue_latency" => JSON::Any.new(default_queue_latency),
        "workers_size"          => JSON::Any.new(workers_size.to_i64),
        "enqueued"              => JSON::Any.new(enqueued.to_i64),
      }
    end

    def reset(stat = nil)
      all = %w(failed processed)
      stats = stat.nil? ? all : all & [stat]

      mset_args = Hash(String, Int32).new
      stats.each do |st|
        mset_args["stat:#{st}"] = 0
      end
      Sidekiq.redis(&.mset(mset_args)) unless mset_args.empty?
    end

    private def stat(s)
      @stats[s]
    end

    class Queues
      def lengths
        result = Hash(String, Int64).new(0_i64)

        Sidekiq.redis do |conn|
          queues = conn.smembers("queues").as(Array(Redis::RedisValue))

          lengths = conn.pipelined do |ppp|
            queues.each do |queue|
              ppp.llen("queue:#{queue}")
            end
          end.as(Array(Redis::RedisValue))

          queues.each_with_index do |name, index|
            result[name.as(String)] = lengths[index].as(Int64)
          end
          nil
        end
        result
      end
    end

    class History
      @days_previous : Int32
      @start_date : Time

      def initialize(days_previous, start_date = nil)
        @days_previous = days_previous
        @start_date = start_date || Time.utc.at_beginning_of_day
      end

      def processed
        date_stat_hash("processed")
      end

      def failed
        date_stat_hash("failed")
      end

      private def date_stat_hash(stat)
        i = 0
        stat_hash = Hash(String, Int32).new
        keys = [] of String
        dates = [] of String

        while i < @days_previous
          date = @start_date - i.days
          datestr = date.to_s("%Y-%m-%d")
          keys << "stat:#{stat}:#{datestr}"
          dates << datestr
          i += 1
        end

        Sidekiq.redis do |conn|
          conn.mget(keys).each_with_index do |value, idx|
            stat_hash[dates[idx]] = value ? value.as(String).to_i : 0
          end
        end

        stat_hash
      end
    end
  end

  # #
  # Encapsulates a pending job within a Sidekiq queue or
  # sorted set.
  #
  # The job should be considered immutable but may be
  # removed from the queue via Job#delete.
  #
  class JobProxy
    getter value : String

    @job : Job

    def initialize(str)
      @job = Job.from_json(str)
      @value = str
    end

    delegate args, to: @job
    delegate created_at, to: @job
    delegate error_backtrace, to: @job
    delegate enqueued_at, to: @job
    delegate error_class, to: @job
    delegate error_message, to: @job
    delegate failed_at, to: @job
    delegate jid, to: @job
    delegate klass, to: @job
    delegate queue, to: @job
    delegate retried_at, to: @job
    delegate retry_count, to: @job
    delegate to_json, to: @job
    delegate extra_params, to: @job

    def display_class
      # TODO Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      klass
    end

    def display_args : String
      # TODO Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      args
    end

    def latency
      (Time.utc - (enqueued_at || created_at)).to_f
    end

    # #
    # Remove this job from the queue.
    def delete : Bool
      count = Sidekiq.redis do |conn|
        conn.lrem("queue:#{queue}", 1, @value)
      end.as(Int64)
      count != 0
    end
  end

  # #
  # Encapsulates a queue within Sidekiq.
  # Allows enumeration of all jobs within the queue
  # and deletion of jobs.
  #
  #   queue = Sidekiq::Queue.new("mailer")
  #   queue.each do |job|
  #     job.klass # => "MyWorker"
  #     job.args # => [1, 2, 3]
  #     job.delete if job.jid == "abcdef1234567890"
  #   end
  #
  class Queue
    include Enumerable(Sidekiq::JobProxy)

    # #
    # Return all known queues within Redis.
    #
    def self.all
      Sidekiq.redis(&.smembers("queues")).compact_map do |name|
        Sidekiq::Queue.new(name) if name.is_a?(String)
      end.sort_by!(&.name)
    end

    getter name : String

    def initialize(name = "default")
      @name = name
      @rname = "queue:#{name}"
    end

    def size
      Sidekiq.redis(&.llen(@rname))
    end

    # Sidekiq Pro overrides this
    def paused?
      false
    end

    # #
    # Calculates this queue's latency, the difference in seconds since the oldest
    # job in the queue was enqueued.
    #
    # @return Float64
    def latency
      entries = Sidekiq.redis do |conn|
        conn.lrange(@rname, -1, -1)
      end.as(Array(Redis::RedisValue))
      return 0 unless entries.size == 1
      msg = entries[0].as(String)

      hash = JSON.parse(msg).as_h
      was = hash["enqueued_at"].as_f
      Time.local.to_unix_f - was
    end

    def each
      initial_size = size
      deleted_size = 0
      page = 0
      page_size = 50

      loop do
        range_start = page * page_size - deleted_size
        range_end = range_start + page_size - 1
        entries = Sidekiq.redis do |conn|
          conn.lrange @rname, range_start, range_end
        end.as(Array(Redis::RedisValue))
        break if entries.empty?
        page += 1
        entries.each do |entry|
          yield JobProxy.new(entry.as(String))
        end
        deleted_size = initial_size - size
      end
    end

    # #
    # Find the job with the given JID within this queue.
    #
    # **This is a slow, inefficient operation.**  Do not use under
    # normal conditions.  Sidekiq Pro contains a faster version.
    def find_job(jid)
      find { |j| j.jid == jid }
    end

    def clear
      Sidekiq.redis do |conn|
        conn.multi do |m|
          m.del(@rname)
          m.srem("queues", name)
        end
      end
    end
  end

  class SortedEntry < JobProxy
    getter score : Float64
    getter parent : Sidekiq::JobSet?

    def initialize(parent, score, item)
      super(item)
      @score = score
      @parent = parent
    end

    def at
      Time.unix_ms((score * 1000).to_i64)
    end

    def delete
      p = @parent.not_nil!
      if @value
        p.delete_by_value(p.name, @value)
      else
        p.delete_by_jid(score, jid)
      end
    end

    def reschedule(at)
      delete
      p = @parent.not_nil!
      p.schedule(at, to_json)
    end

    def add_to_queue
      remove_job do |message|
        job = Sidekiq::Job.from_json(message)
        Sidekiq::Client.new.push(job)
      end
    end

    def retry!
      raise "Retry not available on jobs which have not failed" unless failed_at
      remove_job do |message|
        job = Sidekiq::Job.from_json(message)
        job.retry_count = job.retry_count.not_nil! - 1
        Sidekiq::Client.new.push(job)
      end
    end

    # #
    # Place job in the dead set
    def kill!
      raise "Kill not available on jobs which have not failed" unless failed_at
      remove_job do |message|
        now = Time.local.to_unix_f
        Sidekiq.redis do |conn|
          conn.multi do |m|
            m.zadd("dead", now, message)
            m.zremrangebyscore("dead", "-inf", now - DeadSet.timeout)
            m.zremrangebyrank("dead", 0, -DeadSet.max_jobs)
          end
        end
      end
    end

    private def remove_job
      p = @parent.not_nil!
      arr = [] of String

      Sidekiq.redis do |conn|
        results = conn.multi do |m|
          m.zrangebyscore(p.name, score, score)
          m.zremrangebyscore(p.name, score, score)
        end.as(Array(Redis::RedisValue)).first

        r = results.as(Array(Redis::RedisValue))
        r.each do |msg|
          arr << msg.as(String)
        end
      end

      if arr.size == 1
        yield arr.first
      else
        # multiple jobs with the same score
        # find the one with the right JID and push it
        msg = nil
        hash = arr.group_by do |message|
          msg = message
          if msg.index(jid)
            h = JSON.parse(msg).as_h
            h["jid"] == jid
          else
            false
          end
        end

        msg = hash.fetch(true, [] of String).first?
        yield msg if msg

        # push the rest back onto the sorted set
        Sidekiq.redis do |conn|
          conn.multi do |m|
            hash.fetch(false, [] of String).each do |message|
              m.zadd(p.name, score.to_f.to_s, message)
            end
          end
        end
      end
    end
  end

  class SortedSet
    getter name : String
    @_size : Int32

    def initialize(@name)
      @_size = Sidekiq.redis(&.zcard(@name)).to_i32
    end

    def size
      Sidekiq.redis(&.zcard(@name))
    end

    def clear
      Sidekiq.redis do |conn|
        conn.del(name)
      end
    end
  end

  class JobSet < SortedSet
    include Enumerable(SortedEntry)

    def schedule(timestamp, json_message : String)
      Sidekiq.redis do |conn|
        conn.zadd(name, timestamp.to_f.to_s, json_message)
      end
    end

    def each
      initial_size = @_size
      offset_size = 0
      page = -1
      page_size = 50

      loop do
        range_start = page * page_size + offset_size
        range_end = range_start + page_size - 1
        elements = Sidekiq.redis do |conn|
          conn.zrange name, range_start, range_end, with_scores: true
        end.as(Array(Redis::RedisValue))
        break if elements.empty?
        page -= 1
        elements.in_groups_of(2).each do |(element, score)|
          msg = element.not_nil!.as(String)
          at = score.not_nil!.as(String).to_f
          yield SortedEntry.new(self, at, msg)
        end
        offset_size = initial_size - @_size
      end
    end

    def fetch(score, jid = nil)
      elements = Sidekiq.redis do |conn|
        conn.zrangebyscore(name, score, score)
      end.as(Array(Redis::RedisValue))

      elements.compact_map do |element|
        entry = SortedEntry.new(self, score, element.as(String))
        entry if jid.nil? || entry.jid == jid
      end
    end

    # #
    # Find the job with the given JID within this sorted set.
    #
    # This is a slow, inefficient operation.  Do not use under
    # normal conditions.  Sidekiq Pro contains a faster version.
    def find_job(jid)
      self.find { |j| j.jid == jid }
    end

    def delete_by_value(name, value)
      Sidekiq.redis do |conn|
        ret = conn.zrem(name, value)
        @_size -= 1 if ret
        ret
      end
    end

    def delete_by_jid(score, jid)
      removed = false
      Sidekiq.redis do |conn|
        elements = conn.zrangebyscore(name, score, score).as(Array(Redis::RedisValue))
        elements.each do |element|
          message = JSON.parse(element.as(String)).as_h
          if message["jid"] == jid
            ret = conn.zrem(name, element)
            if ret
              @_size -= 1
              removed = true
            end
            break
          end
        end
        nil
      end
      removed
    end
  end

  # #
  # Allows enumeration of scheduled jobs within Sidekiq.
  # Based on this, you can search/filter for jobs.  Here"s an
  # example where I"m selecting all jobs of a certain type
  # and deleting them from the retry queue.
  #
  #   r = Sidekiq::ScheduledSet.new
  #   r.select do |retri|
  #     retri.klass == "Sidekiq::Extensions::DelayedClass" &&
  #     retri.args[0] == "User" &&
  #     retri.args[1] == "setup_new_subscriber"
  #   end.map(&:delete)
  class ScheduledSet < JobSet
    def initialize
      super "schedule"
    end
  end

  # #
  # Allows enumeration of retries within Sidekiq.
  # Based on this, you can search/filter for jobs.  Here"s an
  # example where I"m selecting all jobs of a certain type
  # and deleting them from the retry queue.
  #
  #   r = Sidekiq::RetrySet.new
  #   r.select do |retri|
  #     retri.klass == "Sidekiq::Extensions::DelayedClass" &&
  #     retri.args[0] == "User" &&
  #     retri.args[1] == "setup_new_subscriber"
  #   end.map(&:delete)
  class RetrySet < JobSet
    def initialize
      super "retry"
    end

    def retry_all
      while size > 0
        each(&.retry!)
      end
    end
  end

  # #
  # Allows enumeration of dead jobs within Sidekiq.
  #
  class DeadSet < JobSet
    def initialize
      super "dead"
    end

    def retry_all
      while size > 0
        each(&.retry!)
      end
    end

    def self.max_jobs
      10_000
    end

    def self.timeout
      6 * 30 * 24 * 60 * 60
    end
  end

  #
  # Sidekiq::Process represents an active Sidekiq process talking with Redis.
  # Each process has a set of attributes which look like this:
  #
  # {
  #   "hostname" => "app-1.example.com",
  #   "started_at" => <process start time>,
  #   "pid" => 12345,
  #   "tag" => "myapp"
  #   "concurrency" => 25,
  #   "queues" => ["default", "low"],
  #   "busy" => 10,
  #   "beat" => <last heartbeat>,
  #   "identity" => <unique string identifying the process>,
  # }
  class Process
    def initialize(hash : Hash(String, JSON::Any))
      @attribs = hash
    end

    def started_at
      Time.unix_ms((self["started_at"].as_f * 1000).to_i64)
    end

    def tag
      @attribs["tag"]?
    end

    def labels
      x = @attribs["labels"]?
      x ? x.as_a.map(&.as_s) : [] of String
    end

    def queues
      self["queues"].as_a.map(&.as_s)
    end

    def [](key)
      @attribs[key]
    end

    def quiet!
      signal("USR1")
    end

    def stop!
      signal("TERM")
    end

    def dump_threads
      signal("TTIN")
    end

    def stopping?
      self["quiet"] == "true"
    end

    private def signal(sig)
      key = "#{identity}-signals"
      Sidekiq.redis do |c|
        c.multi do |m|
          m.lpush(key, sig)
          m.expire(key, 60)
        end
      end
    end

    def identity
      self["identity"]
    end
  end

  # #
  # Enumerates the set of Sidekiq processes which are actively working
  # right now.  Each process send a heartbeat to Redis every 5 seconds
  # so this set should be relatively accurate, barring network partitions.
  #
  # Yields a Sidekiq::Process.
  #
  class ProcessSet
    include Enumerable(Sidekiq::Process)

    def initialize(clean_plz = true)
      self.class.cleanup if clean_plz
    end

    # Cleans up dead processes recorded in Redis.
    # Returns the number of processes cleaned.
    def self.cleanup
      count = 0
      Sidekiq.redis do |conn|
        prcs = conn.smembers("processes")
        procs = [] of String
        prcs.each { |x| procs << x.as(String) }

        heartbeats = conn.pipelined do |ppp|
          procs.each do |key|
            ppp.hget(key, "info")
          end
        end.as(Array(Redis::RedisValue))
        beats = [] of String?
        heartbeats.each { |x| beats << (x ? x.as(String) : nil) }

        # the hash named key has an expiry of 60 seconds.
        # if it's not found, that means the process has not reported
        # in to Redis and probably died.
        to_prune = [] of String
        beats.each_with_index do |beat, i|
          to_prune << procs[i] unless beat
        end

        count = conn.srem("processes", to_prune) unless to_prune.empty?
      end
      count
    end

    def each
      Sidekiq.redis do |conn|
        prcs = conn.smembers("processes")
        procs = [] of String
        prcs.each { |x| procs << x.as(String) }
        procs.sort!

        # We're making a tradeoff here between consuming more memory instead of
        # making more roundtrips to Redis, but if you have hundreds or thousands of workers,
        # you'll be happier this way
        results = conn.pipelined do |ppp|
          procs.each do |key|
            ppp.hmget(key, "info", "busy", "beat", "quiet")
          end
        end.as(Array(Redis::RedisValue))

        results.each do |x|
          packet = x.as(Array(Redis::RedisValue))
          info = packet[0].as(String)
          busy = packet[1].as(String).to_i64
          beat = packet[2].as(String).to_f64
          quiet = packet[3]?.to_s == "true"

          hash = JSON.parse(info).as_h
          hash["busy"] = JSON::Any.new(busy)
          hash["beat"] = JSON::Any.new(beat)
          hash["quiet"] = JSON::Any.new(quiet)
          yield Process.new(hash)
        end
      end

      nil
    end

    # This method is not guaranteed accurate since it does not prune the set
    # based on current heartbeat.  #each does that and ensures the set only
    # contains Sidekiq processes which have sent a heartbeat within the last
    # 60 seconds.
    def size
      Sidekiq.redis(&.scard("processes"))
    end
  end

  class WorkerEntry
    getter! process_id : String
    getter! thread_id : String
    getter! work : Hash(String, JSON::Any)

    def initialize(@process_id, @thread_id, @work)
    end

    def job_proxy : JobProxy
      Sidekiq::JobProxy.new(work["payload"].to_json)
    end

    def run_at : Time
      Time.unix(work["run_at"].as_i)
    end
  end

  # #
  # A worker is a thread that is currently processing a job.
  # Programmatic access to the current active worker set.
  #
  # WARNING WARNING WARNING
  #
  # This is live data that changes second by second.
  # If you call #size => 5 and then expect #each to be
  # called 5 times, you're going to have a bad time.
  #
  #    workers = Sidekiq::Workers.new
  #    workers.size => 2
  #    workers.each do |process_id, thread_id, work|
  #      # process_id is a unique identifier per Sidekiq process
  #      # thread_id is a unique identifier per thread
  #      # work is a Hash which looks like:
  #      # { "queue" => name, "run_at" => timestamp, "payload" => msg }
  #      # run_at is an epoch Integer.
  #    end
  #
  class Workers
    include Enumerable(WorkerEntry)

    def each
      workers_set = [] of Array(String)
      keys = [] of String
      Sidekiq.redis do |conn|
        prcs = conn.smembers("processes")
        procs = [] of String
        prcs.each { |x| procs << x.as(String) }
        procs.sort!

        procs.each do |key|
          valid, workers = conn.pipelined do |ppp|
            ppp.exists(key)
            ppp.hgetall("#{key}:workers")
          end
          next unless valid == 1
          keys << key

          w = workers.as(Array(Redis::RedisValue))
          comrades = w.map { |y| y.as(String) }
          workers_set << comrades
        end
        nil
      end
      keys.zip(workers_set).each do |(key, workers)|
        workers.in_groups_of(2).each do |(tid, json)|
          yield(WorkerEntry.new(key, tid, JSON.parse(json.not_nil!).as_h))
        end
      end
    end

    # Note that #size is only as accurate as Sidekiq's heartbeat,
    # which happens every 5 seconds.  It is NOT real-time.
    #
    # Not very efficient if you have lots of Sidekiq
    # processes but the alternative is a global counter
    # which can easily get out of sync with crashy processes.
    def size
      count = 0
      Sidekiq.redis do |conn|
        procs = conn.smembers("processes")
        unless procs.empty?
          res = conn.pipelined do |ppp|
            procs.each do |key|
              ppp.hget(key.to_s, "busy")
            end
          end
          count = res.sum { |x| x.nil? ? 0 : x.as(String).to_i }
        end
      end
      count
    end
  end
end
