require "./job"

module Sidekiq
  class Stats
    @stats : Hash(String, JSON::Type)

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
          procs.each { |key| ppp.hget(key, "busy") }
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
                                Time.now.epoch_f - was
                              else
                                0.0_f64
                              end
      Hash(String, JSON::Type){
        "processed"      => pipe1_res[0] ? pipe1_res[0].as(String).to_i64 { 0_i64 } : 0_i64,
        "failed"         => pipe1_res[1] ? pipe1_res[1].as(String).to_i64 { 0_i64 } : 0_i64,
        "scheduled_size" => pipe1_res[2].as(Int64),
        "retry_size"     => pipe1_res[3].as(Int64),
        "dead_size"      => pipe1_res[4].as(Int64),
        "processes_size" => pipe1_res[5].as(Int64),

        "default_queue_latency" => default_queue_latency,
        "workers_size"          => workers_size.to_i64,
        "enqueued"              => enqueued.to_i64,
      }
    end

    def reset(stat = nil)
      all = %w(failed processed)
      stats = stat.nil? ? all : all & [stat]

      mset_args = Hash(String, Int32).new
      stats.each do |stat|
        mset_args["stat:#{stat}"] = 0
      end
      Sidekiq.redis do |conn|
        conn.mset(mset_args)
      end unless mset_args.empty?
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
        @start_date = start_date || Time.now.to_utc.date
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
          date = @start_date - i
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
  class JobProxy < ::Sidekiq::Job
    getter item : Hash(String, JSON::Type)
    getter value : String

    def initialize(str)
      super(JSON::PullParser.new(str))
      @value = str
      @item = JSON.parse(str).as_h
    end

    def display_class
      # TODO Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      klass
    end

    def display_args : String
      # TODO Unwrap known wrappers so they show up in a human-friendly manner in the Web UI
      args
    end

    def latency
      (Time.now.to_utc - (enqueued_at || created_at)).to_f
    end

    # #
    # Remove this job from the queue.
    def delete
      count = Sidekiq.redis do |conn|
        conn.lrem("queue:#{@queue}", 1, @value)
      end.as(Int64)
      count != 0
    end

    def [](name)
      @item[name]
    end

    def []?(name)
      @item[name]?
    end

    private def safe_load(content, default)
      begin
        yield(*YAML.load(content))
      rescue ex
        # #1761 in dev mode, it"s possible to have jobs enqueued which haven"t been loaded into
        # memory yet so the YAML can"t be loaded.
        puts "Unable to load YAML: #{ex.message}"
        default
      end
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
      Sidekiq.redis { |c| c.smembers("queues") }.as(Array).map { |x| x.as(String) }.sort.map { |q| Sidekiq::Queue.new(q) }
    end

    getter name : String

    def initialize(name = "default")
      @name = name
      @rname = "queue:#{name}"
    end

    def size
      Sidekiq.redis { |con| con.llen(@rname) }
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
      was = hash["enqueued_at"].as(Float64)
      Time.now.epoch_f - was
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
      Time.epoch_ms((score * 1000).to_i64)
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
      p.schedule(at, item)
    end

    def add_to_queue
      remove_job do |message|
        job = Sidekiq::Job.from_json(message)
        Sidekiq::Client.new.push(job)
      end
    end

    def retry!
      raise "Retry not available on jobs which have not failed" unless item["failed_at"]
      remove_job do |message|
        job = Sidekiq::Job.from_json(message)
        job.retry_count = job.retry_count.not_nil! - 1
        Sidekiq::Client.new.push(job)
      end
    end

    # #
    # Place job in the dead set
    def kill!
      raise "Kill not available on jobs which have not failed" unless item["failed_at"]
      remove_job do |message|
        now = Time.now.epoch_f
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
      Sidekiq.redis do |conn|
        results = conn.multi do |m|
          m.zrangebyscore(p.name, score, score)
          m.zremrangebyscore(p.name, score, score)
        end.as(Array(Redis::RedisValue)).first

        r = results.as(Array(Redis::RedisValue))
        arr = [] of String
        r.each do |msg|
          arr << msg.as(String)
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

    def initialize(name)
      @name = name
      @_size = Sidekiq.redis { |c| c.zcard(name) }.to_i32
    end

    def size
      Sidekiq.redis { |c| c.zcard(name) }
    end

    def clear
      Sidekiq.redis do |conn|
        conn.del(name)
      end
    end
  end

  class JobSet < SortedSet
    include Enumerable(SortedEntry)

    def schedule(timestamp, message)
      Sidekiq.redis do |conn|
        conn.zadd(name, timestamp.to_f.to_s, message.to_json)
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

      result = [] of SortedEntry
      elements.reduce(result) do |result, element|
        entry = SortedEntry.new(self, score, element.as(String))
        if jid
          result << entry if entry.jid == jid
        else
          result << entry
        end
        result
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
    def initialize(hash : Hash(String, JSON::Type))
      @attribs = hash
    end

    def started_at
      Time.epoch_ms((self["started_at"].as(Float64) * 1000).to_i64)
    end

    def tag
      @attribs["tag"]?
    end

    def labels
      x = @attribs["labels"]?
      x ? x.as(Array).map { |x| x.as(String) } : [] of String
    end

    def queues
      self["queues"].as(Array).map { |x| x.as(String) }
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
          hash["busy"] = busy
          hash["beat"] = beat
          hash["quiet"] = quiet
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
      Sidekiq.redis { |conn| conn.scard("processes") }
    end
  end

  class WorkerEntry
    getter! process_id : String
    getter! thread_id : String
    getter! work : Hash(String, JSON::Type)

    def initialize(@process_id, @thread_id, @work)
    end

    def job_proxy : JobProxy
      Sidekiq::JobProxy.new(work["payload"].to_json)
    end

    def run_at : Time
      Time.epoch(work["run_at"].as(Int))
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
              ppp.hget(key, "busy")
            end
          end
          arr = res.as(Array(Redis::RedisValue))
          res.compact.each { |x| count += x.as(String).to_i }
        end
      end
      count
    end
  end
end
