require "./spec_helper"
require "../src/sidekiq/web"

describe "sidekiq web" do
  it "can show text with any locales" do
    empty = {} of String => String
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "ru,en"}
    get "/", empty, rackenv
    assert_match(/Панель управления/, last_response.body)
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "es,en"}
    get "/", empty, rackenv
    assert_match(/Panel de Control/, last_response.body)
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "en-us"}
    get "/", empty, rackenv
    assert_match(/Dashboard/, last_response.body)
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "zh-cn"}
    get "/", empty, rackenv
    assert_match(/信息板/, last_response.body)
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "zh-tw"}
    get "/", empty, rackenv
    assert_match(/資訊主頁/, last_response.body)
    rackenv = {"HTTP_ACCEPT_LANGUAGE" => "nb"}
    get "/", empty, rackenv
    assert_match(/Oversikt/, last_response.body)
  end

  describe "assets" do
    it "serves static files" do
      resp = get("/images/logo.png")
      resp.headers["Content-Type"].should eq("application/octet-stream")
      content = resp.body
      content.should eq(File.read("src/web/assets/images/logo.png"))
    end
  end

  describe "busy" do
    it "can display workers" do
      add_worker
      assert_equal ["1001"], Sidekiq::Workers.new.map { |entry| entry.thread_id }

      get "/busy"
      assert_equal 200, last_response.status_code
      assert_match(/status-active/, last_response.body)
      assert_match(/critical/, last_response.body)
      assert_match(/HardWorker/, last_response.body)
    end

    it "can quiet a process" do
      identity = "identity"
      signals_key = "#{identity}-signals"

      Sidekiq.redis { |c| c.lpop signals_key }.should be_nil
      post "/busy", {"quiet" => "1", "identity" => identity}
      assert_equal 302, last_response.status_code
      assert_equal "USR1", Sidekiq.redis { |c| c.lpop signals_key }
    end

    it "can stop a process" do
      identity = "identity"
      signals_key = "#{identity}-signals"

      Sidekiq.redis { |c| c.lpop signals_key }.should be_nil
      post "/busy", {"stop" => "1", "identity" => identity}
      assert_equal 302, last_response.status_code
      assert_equal "TERM", Sidekiq.redis { |c| c.lpop signals_key }
    end
  end

  it "can display queues" do
    WebWorker.async("foo").perform(1_i64, 3_i64)

    get "/queues"
    assert_equal 200, last_response.status_code
    assert_match(/foo/, last_response.body)
    refute_match(/HardWorker/, last_response.body)
  end

  it "handles queue view" do
    get "/queues/default"
    assert_equal 200, last_response.status_code
  end

  it "can delete a queue" do
    WebWorker.async("foo").perform(1_i64, 2_i64).should_not be_nil

    get "/queues/foo"
    assert_equal 200, last_response.status_code

    post "/queues/foo"
    assert_equal 302, last_response.status_code

    Sidekiq.redis do |conn|
      conn.smembers("queues").includes?("foo").should be_false
      conn.exists("queue:foo").should eq(0)
    end
  end

  it "can delete a job" do
    WebWorker.async("foo").perform(1_i64, 2_i64).should_not be_nil
    jid = WebWorker.async("foo").perform(2_i64, 4_i64)
    jid.should_not be_nil
    WebWorker.async("foo").perform(3_i64, 6_i64).should_not be_nil
    job = Sidekiq::Queue.new("foo").find_job(jid).not_nil!

    get "/queues/foo"
    assert_equal 200, last_response.status_code

    Sidekiq.redis do |conn|
      conn.lrange("queue:foo", 0, -1).includes?(job.value).should be_true
    end

    post "/queues/foo/delete", {"key_val" => job.value}
    assert_equal 302, last_response.status_code

    Sidekiq.redis do |conn|
      conn.lrange("queue:foo", 0, -1).includes?(job.value).should be_false
    end
  end

  it "can display retries" do
    get "/retries"
    assert_equal 200, last_response.status_code
    assert_match(/found/, last_response.body)
    refute_match(/HardWorker/, last_response.body)

    add_retry

    get "/retries"
    assert_equal 200, last_response.status_code
    refute_match(/found/, last_response.body)
    assert_match(/HardWorker/, last_response.body)
  end

  it "can display a single retry" do
    params = add_retry
    get "/retries/0-shouldntexist"
    assert_equal 302, last_response.status_code
    get "/retries/#{job_params(*params)}"
    assert_equal 200, last_response.status_code
    assert_match(/HardWorker/, last_response.body)
  end

  it "handles missing retry" do
    get "/retries/0-shouldntexist"
    assert_equal 302, last_response.status_code
  end

  it "can delete a single retry" do
    params = add_retry
    post "/retries/#{job_params(*params)}", {"delete" => "Delete"}
    assert_equal 302, last_response.status_code
    assert_equal "/retries", last_response.headers["Location"]

    get "/retries"
    assert_equal 200, last_response.status_code
    refute_match(/#{params[1]}/, last_response.body)
  end

  it "can delete all retries" do
    3.times { add_retry }

    post "/retries/all/delete", {"delete" => "Delete"}
    assert_equal 0, Sidekiq::RetrySet.new.size
    assert_equal 302, last_response.status_code
    assert_equal "/retries", last_response.headers["Location"]
  end

  it "can retry a single retry now" do
    params = add_retry
    post "/retries/#{job_params(*params)}", {"retry" => "Retry"}
    assert_equal 302, last_response.status_code
    assert_equal "/retries", last_response.headers["Location"]

    get "/queues/default"
    assert_equal 200, last_response.status_code
    msg = params[0]
    assert_match(/#{params[1]}/, last_response.body)
  end

  it "can kill a single retry now" do
    params = add_retry
    post "/retries/#{job_params(*params)}", {"kill" => "Kill"}
    assert_equal 302, last_response.status_code
    assert_equal "/retries", last_response.headers["Location"]

    get "/morgue"
    assert_equal 200, last_response.status_code
    assert_match(/#{params[1]}/, last_response.body)
  end

  it "can display scheduled" do
    get "/scheduled"
    assert_equal 200, last_response.status_code
    assert_match(/found/, last_response.body)
    refute_match(/HardWorker/, last_response.body)

    add_scheduled

    get "/scheduled"
    assert_equal 200, last_response.status_code
    refute_match(/found/, last_response.body)
    assert_match(/HardWorker/, last_response.body)
  end

  it "can display a single scheduled job" do
    params = add_scheduled
    get "/scheduled/0-shouldntexist"
    assert_equal 302, last_response.status_code
    get "/scheduled/#{job_params(*params)}"
    assert_equal 200, last_response.status_code
    assert_match(/HardWorker/, last_response.body)
  end

  it "handles missing scheduled job" do
    get "/scheduled/0-shouldntexist"
    assert_equal 302, last_response.status_code
  end

  it "can add to queue a single scheduled job" do
    params = add_scheduled
    post "/scheduled/#{job_params(*params)}", {"add_to_queue" => "true"}
    assert_equal 302, last_response.status_code
    assert_equal "/scheduled", last_response.headers["Location"]

    get "/queues/default"
    assert_equal 200, last_response.status_code
    assert_match(/#{params[1]}/, last_response.body)
  end

  it "can delete a single scheduled job" do
    params = add_scheduled
    post "/scheduled/#{job_params(*params)}", {"delete" => "Delete"}
    assert_equal 302, last_response.status_code
    assert_equal "/scheduled", last_response.headers["Location"]

    get "/scheduled"
    assert_equal 200, last_response.status_code
    refute_match(/#{params[1]}/, last_response.body)
  end

  it "can delete scheduled" do
    params = add_scheduled
    Sidekiq.redis do |conn|
      assert_equal 1, conn.zcard("schedule")
      post "/scheduled", {"key" => job_params(*params), "delete" => "Delete"}
      assert_equal 302, last_response.status_code
      assert_equal "/scheduled", last_response.headers["Location"]
      assert_equal 0, conn.zcard("schedule")
    end
  end

  it "can move scheduled to default queue" do
    q = Sidekiq::Queue.new
    params = add_scheduled
    Sidekiq.redis do |conn|
      assert_equal 1, conn.zcard("schedule")
      assert_equal 0, q.size
      post "/scheduled", {"key" => job_params(*params), "add_to_queue" => "AddToQueue"}
      assert_equal 302, last_response.status_code
      assert_equal "/scheduled", last_response.headers["Location"]
      assert_equal 0, conn.zcard("schedule")
      assert_equal 1, q.size
      get "/queues/default"
      assert_equal 200, last_response.status_code
      assert_match(/#{params[1]}/, last_response.body)
    end
  end

  it "can retry all retries" do
    msg, score = add_retry
    add_retry

    post "/retries/all/retry", {"retry" => "Retry"}
    assert_equal 302, last_response.status_code
    assert_equal "/retries", last_response.headers["Location"]
    assert_equal 2, Sidekiq::Queue.new("default").size

    get "/queues/default"
    assert_equal 200, last_response.status_code
    assert_match(/#{score}/, last_response.body)
  end

  it "calls updatePage() once when polling" do
    get "/busy", {"poll" => "true"}
    assert_equal 200, last_response.status_code
    assert_equal 1, last_response.body.scan("updatePage(").size
  end

  it "escape job args and error messages" do
    # on /retries page
    params = add_xss_retry
    get "/retries"
    assert_equal 200, last_response.status_code
    assert_match(/FailWorker/, last_response.body)

    last_response.body.should contain("fail message: &lt;a&gt;hello&lt;/a&gt;")
    last_response.body.should_not contain("fail message: <a>hello</a>")

    last_response.body.should contain("args\">&quot;&lt;a&gt;hello&lt;/a&gt;&quot;<")
    last_response.body.should_not contain("args\"><a>hello</a><")

    # on /workers page
    Sidekiq.redis do |conn|
      pro = "foo:1234"
      conn.sadd("processes", pro)
      conn.hmset(pro, {"info" => {"identity" => pro, "hostname" => "foo", "pid" => 1234, "concurrency" => 25, "started_at" => Time.now.epoch_f, "labels" => ["frumduz"], "queues" => ["default"]}.to_json, "busy" => 1, "beat" => Time.now.epoch_f})
      identity = "#{pro}:workers"
      hash = {:queue => "critical", :payload => {"queue" => "foo", "jid" => "12355", "class" => "FailWorker", "args" => ["<a>hello</a>"], "created_at" => Time.now.epoch_f}, :run_at => Time.now.epoch}
      conn.hmset(identity, {"100001" => hash.to_json})
      conn.incr("busy")
    end

    get "/busy"
    assert_equal 200, last_response.status_code
    assert_match(/FailWorker/, last_response.body)
    assert_match(/frumduz/, last_response.body)
    last_response.body.should contain("&lt;a&gt;hello&lt;/a&gt;")
    last_response.body.should_not contain("<a>hello</a>")

    # on /queues page
    params = add_xss_retry
    post "/retries/#{job_params(*params)}", {"retry" => "Retry"}
    assert_equal 302, last_response.status_code

    get "/queues/foo"
    assert_equal 200, last_response.status_code
    last_response.body.should contain("&lt;a&gt;hello&lt;/a&gt;")
    last_response.body.should_not contain("<a>hello</a>")
  end

  # it "can show user defined tab" do
  # begin
  # Sidekiq::Web.tabs["Custom Tab"] = "/custom"

  # get "/"
  # assert_match "Custom Tab", last_response.body

  # ensure
  # Sidekiq::Web.tabs.delete "Custom Tab"
  # end
  # end

  it "can display home" do
    get "/"
    assert_equal 200, last_response.status_code
  end

  # describe "custom locales" do
  # before do
  # Sidekiq::Web.settings.locales << File.join(File.dirname(__FILE__), "fixtures")
  # Sidekiq::Web.tabs["Custom Tab"] = "/custom"
  # Sidekiq::Web.get("/custom") do
  # clear_caches # ugly hack since I can"t figure out how to access WebHelpers outside of this context
  # t("translated_text")
  # end
  # end

  # after do
  # Sidekiq::Web.tabs.delete "Custom Tab"
  # Sidekiq::Web.settings.locales.pop
  # end

  # it "can show user defined tab with custom locales" do
  # get "/custom"
  # assert_match(/Changed text/, last_response.body)
  # end
  # end

  describe "dashboard/stats" do
    it "redirects to stats" do
      get "/dashboard/stats"
      assert_equal 302, last_response.status_code
      assert_equal "/stats", last_response.headers["Location"]
    end
  end

  describe "stats" do
    it "renders stats" do
      Sidekiq.redis do |conn|
        conn.set("stat:processed", 5)
        conn.set("stat:failed", 2)
        conn.sadd("queues", "default")
      end
      2.times { add_retry }
      3.times { add_scheduled }
      add_worker

      get "/stats"
      response = JSON.parse(last_response.body).as_h
      assert_equal 200, last_response.status_code
      response.keys.should contain "sidekiq"
      hash = response["sidekiq"].as(Hash)
      assert_equal 5, hash["processed"]
      assert_equal 2, hash["failed"]
      assert_equal 4, hash["busy"]
      assert_equal 1, hash["processes"]
      assert_equal 2, hash["retries"]
      assert_equal 3, hash["scheduled"]
      assert_equal 0, hash["default_latency"]
      response.keys.should contain "redis"
      hash = response["redis"].as(Hash)
      hash["redis_version"].should match /\d\.\d\.\d/
      hash["uptime_in_days"].to_s.to_i.should be >= 0
      hash["connected_clients"].to_s.to_i.should be > 0
      hash["used_memory_human"].should_not be_nil
      hash["used_memory_peak_human"].should_not be_nil
    end
  end

  describe "stats/queues" do
    it "reports the queue depth" do
      Sidekiq.redis do |conn|
        conn.sadd("queues", "default")
        conn.sadd("queues", "queue2")
        conn.lpush("queue:default", "{}")
        conn.lpush("queue:default", "{}")
        conn.lpush("queue:default", "{}")
        conn.lpush("queue:queue2", "{}")
        conn.lpush("queue:queue2", "{}")
      end

      get "/stats/queues"
      response = JSON.parse(last_response.body).as_h

      assert_equal 3, response["default"]
      assert_equal 2, response["queue2"]
    end
  end

  describe "dead jobs" do
    it "shows empty index" do
      get "morgue"
      assert_equal 200, last_response.status_code
    end

    it "shows index with jobs" do
      _, score = add_dead
      get "morgue"
      assert_equal 200, last_response.status_code
      assert_match(/#{score}/, last_response.body)
    end

    it "can delete all dead" do
      3.times { add_dead }

      assert_equal 3, Sidekiq::DeadSet.new.size
      post "/morgue/all/delete", {"delete" => "Delete"}
      assert_equal 0, Sidekiq::DeadSet.new.size
      assert_equal 302, last_response.status_code
      assert_equal "/morgue", last_response.headers["Location"]
    end

    it "can retry a dead job" do
      params = add_dead
      post "/morgue/#{job_params(*params)}", {"retry" => "Retry"}, {"http_referer" => "http://example.org/morgue?page=3"}
      assert_equal 302, last_response.status_code
      assert_equal "/morgue?page=3", last_response.headers["Location"]

      get "/queues/foo"
      assert_equal 200, last_response.status_code
      assert_match(/#{params[1]}/, last_response.body)
    end
  end
end

private def add_scheduled
  now = Time.now.epoch_f
  msg = {"class" => "HardWorker",
         "queue" => "default",
         "created_at" => now,
         "args"  => ["bob", 1, now],
         "jid"   => SecureRandom.hex(12)}
  score = now.to_s
  Sidekiq.redis do |conn|
    conn.zadd("schedule", score, msg.to_json)
  end
  {msg, score}
end

private def add_retry
  now = Time.now.epoch_f
  msg = {"class"         => "HardWorker",
    "args"          => ["bob", 1, now.to_s],
    "queue"         => "default",
    "created_at" => now,
    "error_message" => "Some fake message",
    "error_class"   => "RuntimeError",
    "retry_count"   => 0,
    "retried_at"    => now,
    "failed_at"     => now,
    "jid"           => SecureRandom.hex(12)}
  score = now.to_s
  Sidekiq.redis do |conn|
    conn.zadd("retry", score, msg.to_json)
  end
  {msg, score}
end

private def add_dead
  now = Time.now.epoch_f
  msg = {"class"         => "HardWorker",
    "args"          => ["bob", 1, now],
    "queue"         => "foo",
    "created_at" => now,
    "error_message" => "Some fake message",
    "error_class"   => "RuntimeError",
    "retry_count"   => 20,
    "retried_at"    => now,
    "failed_at"     => now,
    "jid"           => SecureRandom.hex(12)}
  score = now.to_s
  Sidekiq.redis do |conn|
    conn.zadd("dead", score, msg.to_json)
  end
  {msg, score}
end

private def add_xss_retry
  now = Time.now.epoch_f
  msg = {"class"         => "FailWorker",
    "args"          => ["<a>hello</a>"],
    "queue"         => "foo",
    "created_at" => now,
    "error_message" => "fail message: <a>hello</a>",
    "error_class"   => "RuntimeError",
    "retry_count"   => 0,
    "failed_at"     => now,
    "jid"           => SecureRandom.hex(12)}
  score = now.to_s
  Sidekiq.redis do |conn|
    conn.zadd("retry", score, msg.to_json)
  end
  {msg, score}
end

private def add_worker
  key = "#{System.hostname}:#{Process.pid}"
  msg = "{\"queue\":\"default\",\"payload\":{\"retry\":true,\"queue\":\"critical\",\"timeout\":20,\"backtrace\":5,\"class\":\"HardWorker\",\"args\":[\"bob\",10,5],\"jid\":\"2b5ad2b016f5e063a1c62872\",\"created_at\":1361208995.1234},\"run_at\":1361208995}"
  Sidekiq.redis do |conn|
    conn.multi do |m|
      m.sadd("processes", key)
      m.hmset(key, {"info" => {"concurrency" => 25, "identity" => key, "pid" => Process.pid, "hostname" => "foo", "started_at" => Time.now.epoch_f, "queues" => ["default", "critical"]}.to_json, "beat" => Time.now.epoch_f, "busy" => 4})
      m.hmset("#{key}:workers", {"1001" => msg})
    end
  end
  key
end

private def last_response
  $last_response.not_nil!
end

private def job_params(msg, score)
  "#{score}-#{msg["jid"]}"
end

class WebWorker
  include Sidekiq::Worker

  def perform(a : Int64, b : Int64)
    a + b
  end
end

private def get(path, params = nil, headers = nil)
  resource = "#{path}?#{params.try(&.map { |k, v| "#{URI.escape(k)}=#{URI.escape(v)}" }.join("&"))}"
  hdrs = HTTP::Headers.new
  headers.each do |k, v|
    hdrs[k] = v
  end if headers
  req = HTTP::Request.new("GET", resource, hdrs)
  io = MemoryIO.new
  $last_response = res = HTTP::Server::Response.new(io)
  res.mem = io
  Kemal::RouteHandler::INSTANCE.call(HTTP::Server::Context.new(req, res))
  res.flush
  res
end

private def post(path, params = nil, headers = nil)
  resource = path
  body = params.try(&.map { |k, v| "#{URI.escape(k, true)}=#{URI.escape(v, true)}" }.join("&"))
  hdrs = HTTP::Headers.new
  headers.each do |k, v|
    hdrs[k] = v
  end if headers
  hdrs["Content-Type"] = "application/x-www-form-urlencoded"
  req = HTTP::Request.new("POST", resource, hdrs, body)
  io = MemoryIO.new
  $last_response = res = HTTP::Server::Response.new(MemoryIO.new)
  res.mem = io
  Kemal::RouteHandler::INSTANCE.call(HTTP::Server::Context.new(req, res))
  res.flush
  res
end
