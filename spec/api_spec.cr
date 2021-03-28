require "./spec_helper"
require "../src/sidekiq/api"

class ApiWorker
  include Sidekiq::Worker

  def perform(foo : Int64, name : String)
  end
end

describe "api" do
  describe "stats" do
    it "is initially zero" do
      s = Sidekiq::Stats.new
      s.processed.should eq(0)
      s.failed.should eq(0)
      s.enqueued.should eq(0)
    end

    describe "processed" do
      it "returns number of processed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:processed", 5) }
        s = Sidekiq::Stats.new
        s.processed.should eq(5)
      end
    end

    describe "failed" do
      it "returns number of failed jobs" do
        Sidekiq.redis { |conn| conn.set("stat:failed", 5) }
        s = Sidekiq::Stats.new
        s.failed.should eq(5)
      end
    end

    describe "reset" do
      it "will reset all stats by default" do
        reset_stats
        Sidekiq::Stats.new.reset
        s = Sidekiq::Stats.new
        s.failed.should eq(0)
        s.processed.should eq(0)
      end

      it "can reset individual stats" do
        reset_stats
        Sidekiq::Stats.new.reset("failed")
        s = Sidekiq::Stats.new
        s.failed.should eq(0)
        s.processed.should eq(5)
      end

      it "ignores anything other than 'failed' or 'processed'" do
        reset_stats
        Sidekiq::Stats.new.reset("xxy")
        s = Sidekiq::Stats.new
        s.failed.should eq(10)
        s.processed.should eq(5)
      end
    end

    describe "queues" do
      it "is initially empty" do
        s = Sidekiq::Stats::Queues.new
        s.lengths.size.should eq(0)
      end

      it "returns a hash of queue and size in order" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:foo", "{}"
          conn.sadd "queues", "foo"

          3.times { conn.rpush "queue:bar", "{}" }
          conn.sadd "queues", "bar"
        end

        Sidekiq::Stats::Queues.new.lengths.should eq(Sidekiq::Stats.new.queues)
      end
    end

    describe "enqueued" do
      it "returns total enqueued jobs" do
        Sidekiq.redis do |conn|
          conn.rpush "queue:foo", "{}"
          conn.sadd "queues", "foo"

          3.times { conn.rpush "queue:bar", "{}" }
          conn.sadd "queues", "bar"
        end

        s = Sidekiq::Stats.new
        s.enqueued.should eq(4)
      end
    end
  end

  describe "with an empty database" do
    it "shows queue as empty" do
      q = Sidekiq::Queue.new
      q.size.should eq(0)
      q.latency.should eq(0)
    end

    it "has no enqueued_at time for jobs enqueued in the future" do
      job_id = ApiWorker.async.perform_in(100.seconds, 1_i64, "foo")
      job = Sidekiq::ScheduledSet.new.find_job(job_id).not_nil!
      job.enqueued_at.should be_nil
    end

    it "has no enqueued_at time for jobs enqueued in the future" do
      job_id = ApiWorker.async.perform_in(100.seconds, 1_i64, "foo")
      job = Sidekiq::ScheduledSet.new.find_job(job_id).not_nil!
      job.enqueued_at.should be_nil
    end

    it "can delete jobs" do
      q = Sidekiq::Queue.new
      ApiWorker.async.perform(1_i64, "mike")
      q.size.should eq(1)

      x = q.first
      x.display_class.should eq("ApiWorker")
      x.display_args.should eq("[1,\"mike\"]")

      q.map(&.delete).should eq([true])
      q.size.should eq(0)
    end

    it "can move scheduled job to queue" do
      remain_id = ApiWorker.async.perform_in(100.seconds, 1_i64, "jason")
      job_id = ApiWorker.async.perform_in(100.seconds, 1_i64, "jason")
      job = Sidekiq::ScheduledSet.new.find_job(job_id).not_nil!
      q = Sidekiq::Queue.new
      job.add_to_queue
      queued_job = q.find_job(job_id).not_nil!
      job_id.should eq(queued_job.jid)
      Sidekiq::ScheduledSet.new.find_job(job_id).should be_nil
      Sidekiq::ScheduledSet.new.find_job(remain_id).should_not be_nil
    end

    it "can find job by id in sorted sets" do
      job_id = ApiWorker.async.perform_in(100.seconds, 1_i64, "jason")
      job = Sidekiq::ScheduledSet.new.find_job(job_id).not_nil!
      job.jid.should eq(job_id)
      job.latency.should be_close(0.0, 0.1)
    end

    it "can find job by id in queues" do
      q = Sidekiq::Queue.new
      job_id = ApiWorker.async.perform(1_i64, "jason")
      job = q.find_job(job_id).not_nil!
      job.jid.should eq(job_id)
    end

    it "can clear a queue" do
      q = Sidekiq::Queue.new
      2.times { ApiWorker.async.perform(1_i64, "mike") }
      q.clear

      Sidekiq.redis do |conn|
        conn.smembers("queues").should_not contain("foo")
        conn.exists("queue:foo").should eq(0)
      end
    end

    it "can fetch by score" do
      same_time = Time.local.to_unix_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      r.fetch(same_time).size.should eq(2)
    end

    it "can fetch by score and jid" do
      same_time = Time.local.to_unix_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      r.fetch(same_time, "bob1").size.should eq(1)
    end

    it "shows empty retries" do
      r = Sidekiq::RetrySet.new
      r.size.should eq(0)
    end

    it "can enumerate retries" do
      add_retry

      r = Sidekiq::RetrySet.new
      r.size.should eq(1)
      array = r.to_a
      array.size.should eq(1)

      retri = array.first
      retri.klass.should eq("ApiWorker")
      retri.queue.should eq("default")
      retri.jid.should eq("bob")
      Time.local.to_unix_f.should be_close(retri.at.to_unix_f, 0.02)
    end

    it "can delete a single retry from score and jid" do
      same_time = Time.local.to_unix_f
      add_retry("bob1", same_time)
      add_retry("bob2", same_time)
      r = Sidekiq::RetrySet.new
      r.size.should eq(2)
      Sidekiq::RetrySet.new.delete_by_jid(same_time, "bob1")
      r.size.should eq(1)
    end

    it "can kill a retry" do
      add_retry
      r = Sidekiq::RetrySet.new
      r.size.should eq(1)
      r.first.kill!
      r.size.should eq(0)
      ds = Sidekiq::DeadSet.new
      ds.size.should eq(1)
      job = ds.first
      job.jid.should eq("bob")
    end

    it "can retry a retry" do
      add_retry
      r = Sidekiq::RetrySet.new
      r.size.should eq(1)
      r.first.retry!
      r.size.should eq(0)
      Sidekiq::Queue.new("default").size.should eq(1)
      job = Sidekiq::Queue.new("default").first
      job.jid.should eq("bob")
      job.retry_count.should eq(1)
    end

    it "can clear retries" do
      add_retry
      add_retry("test")
      r = Sidekiq::RetrySet.new
      r.size.should eq(2)
      r.clear
      r.size.should eq(0)
    end

    it "can enumerate processes" do
      identity_string = "identity_string"
      odata = Hash(String, JSON::Any){
        "pid"        => JSON::Any.new(123_i64),
        "hostname"   => JSON::Any.new(System.hostname),
        "key"        => JSON::Any.new(identity_string),
        "identity"   => JSON::Any.new(identity_string),
        "started_at" => JSON::Any.new(Time.local.to_unix_f - 15),
      }

      time = Time.local.to_unix_f
      Sidekiq.redis do |conn|
        conn.multi do |m|
          m.sadd("processes", odata["key"].to_s)
          m.hmset(odata["key"].as_s, {"info" => odata.to_json, "busy" => 10, "beat" => time})
          m.sadd("processes", "fake:pid")
        end
      end

      ps = Sidekiq::ProcessSet.new.to_a
      ps.size.should eq(1)
      data = ps.first
      data["busy"].should eq(10)
      data["beat"].should eq(time)
      data["pid"].should eq(123)
      data.quiet!
      data.stop!
      signals_string = "#{odata["key"]}-signals"
      Sidekiq.redis { |c| c.lpop(signals_string) }.should eq("TERM")
      Sidekiq.redis { |c| c.lpop(signals_string) }.should eq("USR1")
    end

    it "can enumerate workers" do
      w = Sidekiq::Workers.new
      w.size.should eq(0)

      hn = System.hostname
      key = "#{hn}:#{Process.pid}"
      pdata = {"pid" => Process.pid, "hostname" => hn, "started_at" => Time.local.to_unix}
      Sidekiq.redis do |conn|
        conn.sadd("processes", key)
        conn.hmset(key, {"info" => pdata.to_json, "busy" => 0, "beat" => Time.local.to_unix_f})
      end

      s = "#{key}:workers"
      data = {"payload" => "{}", "queue" => "default", "run_at" => Time.local.to_unix}.to_json
      Sidekiq.redis do |c|
        c.hmset(s, {"1234" => data})
      end

      count = 0
      w.each do |entry|
        entry.process_id.should eq(key)
        entry.thread_id.should eq("1234")
        entry.work["queue"].should eq("default")
        Time.unix(entry.work["run_at"].as_i).year.should eq(Time.local.year)
        count += 1
      end
      count.should eq(1)
    end

    it "can reschedule jobs" do
      add_retry("foo1")
      add_retry("foo2")

      retries = Sidekiq::RetrySet.new
      retries.size.should eq(2)
      retries.count { |r| r.score > (Time.local.to_unix_f + 9) }.should eq(0)

      retries.each do |retri|
        retri.reschedule(Time.local.to_unix_f + 10) if retri.jid == "foo2"
      end

      retries.size.should eq(2)
      retries.count { |r| r.score > (Time.local.to_unix_f + 9) }.should eq(1)
    end

    it "prunes processes which have died" do
      data = {"pid" => rand(10_000), "hostname" => "app#{rand(1_000)}", "started_at" => Time.local.to_unix_f}
      key = "#{data["hostname"]}:#{data["pid"]}"
      Sidekiq.redis do |conn|
        conn.sadd("processes", key)
        conn.hmset(key, {"info" => data.to_json, "busy" => 0, "beat" => Time.local.to_unix_f})
      end

      ps = Sidekiq::ProcessSet.new
      ps.size.should eq(1)
      ps.to_a.size.should eq(1)

      Sidekiq.redis do |conn|
        conn.sadd("processes", "bar:987")
        conn.sadd("processes", "bar:986")
      end

      ps = Sidekiq::ProcessSet.new
      ps.size.should eq(1)
      ps.to_a.size.should eq(1)
    end
  end
end

def add_retry(jid = "bob", at = Time.local.to_unix_f)
  payload = {"class" => "ApiWorker", "created_at" => Time.local.to_unix_f, "args" => [1, "mike"], "queue" => "default", "jid" => jid, "retry_count" => 2, "failed_at" => Time.local.to_unix_f}.to_json
  Sidekiq.redis do |conn|
    conn.zadd("retry", at.to_s, payload)
  end
  nil
end

def reset_stats
  Sidekiq.redis do |conn|
    conn.set("stat:processed", 5)
    conn.set("stat:failed", 10)
  end
end
