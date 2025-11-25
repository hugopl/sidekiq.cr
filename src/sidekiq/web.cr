require "../sidekiq"
require "./api"
require "./web_helpers"
require "./web_fs"
require "./metrics"

require "kemal"
require "kemal-session"
require "kemal-csrf"

module Sidekiq
  module Web
    include Sidekiq::WebHelpers

    DEFAULT_TABS = {
      "Dashboard" => "",
      "Busy"      => "busy",
      "Queues"    => "queues",
      "Retries"   => "retries",
      "Scheduled" => "scheduled",
      "Dead"      => "morgue",
      "Metrics"   => "metrics",
    }

    def self.default_tabs
      DEFAULT_TABS
    end

    def self.custom_tabs
      @@custom_tabs ||= {} of String => String
    end
  end
end

class HTTP::Server::Context
  include Sidekiq::WebHelpers
end

root_path = ""

macro ecr(xxx)
  {% if xxx.starts_with?('_') %}
    render "#{{{__DIR__}}}/../web/views/#{{{xxx}}}.ecr"
  {% else %}
    render "#{{{__DIR__}}}/../web/views/#{{{xxx}}}.ecr", "#{{{__DIR__}}}/../web/views/layout.ecr"
  {% end %}
end

get "/" do |x|
  days = x.params.query.fetch("days", 30).to_i
  redis_info = x.redis_info.select { |k, v| REDIS_KEYS.includes? k }
  stats_history = Sidekiq::Stats::History.new(days)
  processed_history = stats_history.processed
  failed_history = stats_history.failed
  ecr("dashboard")
end

REDIS_KEYS = %w(redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human)

get "/dashboard/stats" do |x|
  x.redirect "#{x.root_path}stats"
end

get "/stats" do |x|
  sidekiq_stats = Sidekiq::Stats.new
  redis_stats = x.redis_info.select { |k, v| REDIS_KEYS.includes? k }

  x.response.content_type = "application/json"
  {
    "sidekiq": {
      "processed":       sidekiq_stats.processed,
      "failed":          sidekiq_stats.failed,
      "busy":            sidekiq_stats.workers_size,
      "processes":       sidekiq_stats.processes_size,
      "enqueued":        sidekiq_stats.enqueued,
      "scheduled":       sidekiq_stats.scheduled_size,
      "retries":         sidekiq_stats.retry_size,
      "dead":            sidekiq_stats.dead_size,
      "default_latency": sidekiq_stats.default_queue_latency,
    },
    "redis": redis_stats,
  }.to_json
end

get "/stats/queues" do |x|
  queue_stats = Sidekiq::Stats::Queues.new

  x.response.content_type = "application/json"
  queue_stats.lengths.to_json
end

get "/busy" do |x|
  ecr("busy")
end

post "/busy" do |x|
  id = x.params.body["identity"]?
  if id
    p = Sidekiq::Process.new({"identity" => JSON::Any.new(id)})
    p.quiet! if x.params.body["quiet"]?
    p.stop! if x.params.body["stop"]?
  else
    x.processes.each do |pro|
      pro.quiet! if x.params.body["quiet"]?
      pro.stop! if x.params.body["stop"]?
    end
  end
  x.redirect "/busy"
end

get "/queues" do |x|
  queues = Sidekiq::Queue.all
  ecr("queues")
end

get "/queues/:name" do |x|
  name = x.params.url["name"]
  queue = Sidekiq::Queue.new(name)
  count = 25
  current_page, total_size, messages = x.list_page("queue:#{name}", x.params.query["page"]?.try(&.to_i) || 1)
  jobs = messages.map { |msg| Sidekiq::JobProxy.new(msg) }
  ecr("queue")
end

post "/queues/:name" do |x|
  name = x.params.url["name"]
  Sidekiq::Queue.new(name).clear
  x.redirect "#{x.root_path}queues"
end

post "/queues/:name/delete" do |x|
  name = x.params.url["name"]
  val = x.params.body["key_val"]
  Sidekiq::JobProxy.new(val).delete
  x.redirect x.url_with_query(x, "#{x.root_path}queues/#{name}")
end

get "/morgue" do |x|
  count = 25
  current_page, total_size, msg = x.zpage("dead", x.params.query["page"]?.try(&.to_i) || 1, count, {reverse: true})
  dead = msg.map { |(msg, score)| Sidekiq::SortedEntry.new(nil, score.to_f, msg) }
  ecr("morgue")
end

get "/morgue/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  dead = Sidekiq::DeadSet.new.fetch(score.to_f, jid).first
  x.redirect "#{root_path}morgue" if dead.nil?
  ecr("dead")
end

post "/morgue" do |x|
  bdy = HTTP::Params.parse(x.request.body.not_nil!.gets_to_end)
  bdy.fetch_all("key").each do |key|
    score, jid = key.split("-")
    job = Sidekiq::DeadSet.new.fetch(score.to_f, jid).first?
    retry_or_delete_or_kill job, x.params.body if job
  end
  x.redirect x.url_with_query(x, "#{x.root_path}morgue")
end

post "/morgue/all/delete" do |x|
  Sidekiq::DeadSet.new.clear
  x.redirect "#{x.root_path}morgue"
end

post "/morgue/all/retry" do |x|
  Sidekiq::DeadSet.new.retry_all
  x.redirect "#{x.root_path}morgue"
end

post "/morgue/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  job = Sidekiq::DeadSet.new.fetch(score.to_f, jid).first?
  retry_or_delete_or_kill job, x.params.body if job
  x.redirect x.url_with_query(x, "#{x.root_path}morgue")
end

get "/retries" do |x|
  count = 25
  current_page, total_size, msgs = x.zpage("retry", x.params.query["page"]?.try(&.to_i) || 1, count)
  retries = msgs.map { |(msg, score)| Sidekiq::SortedEntry.new(nil, score.to_f, msg) }
  ecr("retries")
end

get "/retries/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  retri = Sidekiq::RetrySet.new.fetch(score.to_f, jid).first?
  if retri
    ecr("retry")
  else
    x.redirect x.url_with_query(x, "#{x.root_path}retries")
  end
end

post "/retries" do |x|
  bdy = HTTP::Params.parse(x.request.body.not_nil!.gets_to_end)
  bdy.fetch_all("key").each do |key|
    score, jid = key.split("-")
    job = Sidekiq::RetrySet.new.fetch(score.to_f, jid).first?
    retry_or_delete_or_kill job, x.params.body if job
  end
  x.redirect x.url_with_query(x, "#{x.root_path}retries")
end

post "/retries/all/delete" do |x|
  Sidekiq::RetrySet.new.clear
  x.redirect "#{x.root_path}retries"
end

post "/retries/all/retry" do |x|
  Sidekiq::RetrySet.new.retry_all
  x.redirect "#{x.root_path}retries"
end

post "/retries/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  job = Sidekiq::RetrySet.new.fetch(score.to_f, jid).first?
  retry_or_delete_or_kill job, x.params.body if job
  x.redirect x.url_with_query(x, "#{x.root_path}retries")
end

get "/scheduled" do |x|
  count = 25
  current_page, total_size, msgs = x.zpage("schedule", x.params.query["page"]?.try(&.to_i) || 1, count)
  scheduled = msgs.map { |(msg, score)| Sidekiq::SortedEntry.new(nil, score.to_f, msg) }
  ecr("scheduled")
end

get "/scheduled/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  job = Sidekiq::ScheduledSet.new.fetch(score.to_f, jid).first?
  if job
    ecr("scheduled_job_info")
  else
    x.redirect "#{root_path}scheduled"
  end
end

post "/scheduled" do |x|
  ss = Sidekiq::ScheduledSet.new
  x.params.body.fetch_all("key").each do |key|
    score, jid = key.split("-")
    job = ss.fetch(score.to_f, jid).first?
    delete_or_add_queue job, x.params.body if job
  end
  x.redirect x.url_with_query(x, "#{x.root_path}scheduled")
end

post "/scheduled/:key" do |x|
  element = x.params.url["key"]
  score, jid = element.split("-")
  job = Sidekiq::ScheduledSet.new.fetch(score.to_f, jid).first?
  delete_or_add_queue job, x.params.body if job
  x.redirect x.url_with_query(x, "#{x.root_path}scheduled")
end

# Metrics routes
get "/metrics" do |x|
  period = x.params.query.fetch("period", "1").to_i
  period = 1 if period < 1
  period = 72 if period > 72

  end_time = Time.utc
  start_time = end_time - period.hours

  job_classes = Sidekiq::Metrics::Query.job_classes
  metrics_data = Hash(String, NamedTuple(success: Int64, failure: Int64, total_ms: Float64)).new

  job_classes.each do |job_class|
    data = Sidekiq::Metrics::Query.fetch(job_class, start_time, end_time)
    metrics_data[job_class] = Sidekiq::Metrics::Query.aggregate(data)
  end

  ecr("metrics")
end

get "/metrics/data" do |x|
  period = x.params.query.fetch("period", "1").to_i
  period = 1 if period < 1
  period = 72 if period > 72

  job_class = x.params.query["job_class"]?
  end_time = Time.utc
  start_time = end_time - period.hours

  x.response.content_type = "application/json"

  if job_class
    # Fetch data for a specific job class
    data = Sidekiq::Metrics::Query.fetch(job_class, start_time, end_time)

    # Build series data for chart
    series = [] of NamedTuple(time: String, s: Int64, f: Int64, ms: Float64)
    data.keys.sort.each do |ts|
      metrics = data[ts]
      series << {
        time: Time.unix(ts).to_s("%Y-%m-%dT%H:%M:%SZ"),
        s:    metrics["s"]?.try(&.to_i64) || 0_i64,
        f:    metrics["f"]?.try(&.to_i64) || 0_i64,
        ms:   metrics["ms"]?.try(&.to_f64) || 0.0,
      }
    end

    totals = Sidekiq::Metrics::Query.aggregate(data)

    # Build histogram data
    histogram = Array(Int64).new(Sidekiq::Metrics::Histogram::BUCKET_COUNT, 0_i64)
    data.each_value do |metrics|
      (0...Sidekiq::Metrics::Histogram::BUCKET_COUNT).each do |i|
        bucket_val = metrics["h#{i}"]?.try(&.to_i64) || 0_i64
        histogram[i] += bucket_val
      end
    end

    {
      job_class: job_class,
      period:    period,
      series:    series,
      totals:    totals,
      histogram: histogram,
    }.to_json
  else
    # Fetch aggregate data for all job classes
    job_classes = Sidekiq::Metrics::Query.job_classes
    summary = [] of NamedTuple(job_class: String, success: Int64, failure: Int64, total_ms: Float64, avg_ms: Float64)

    job_classes.each do |jc|
      data = Sidekiq::Metrics::Query.fetch(jc, start_time, end_time)
      totals = Sidekiq::Metrics::Query.aggregate(data)
      total_jobs = totals[:success] + totals[:failure]
      avg_ms = total_jobs > 0 ? totals[:total_ms] / totals[:success] : 0.0

      summary << {
        job_class: jc,
        success:   totals[:success],
        failure:   totals[:failure],
        total_ms:  totals[:total_ms],
        avg_ms:    avg_ms,
      }
    end

    {
      period:  period,
      summary: summary,
    }.to_json
  end
end

get "/metrics/:job_class" do |x|
  job_class = x.params.url["job_class"]
  period = x.params.query.fetch("period", "1").to_i
  period = 1 if period < 1
  period = 72 if period > 72

  end_time = Time.utc
  start_time = end_time - period.hours

  data = Sidekiq::Metrics::Query.fetch(job_class, start_time, end_time)
  totals = Sidekiq::Metrics::Query.aggregate(data)

  # Build histogram data
  histogram = Array(Int64).new(Sidekiq::Metrics::Histogram::BUCKET_COUNT, 0_i64)
  data.each_value do |metrics|
    (0...Sidekiq::Metrics::Histogram::BUCKET_COUNT).each do |i|
      bucket_val = metrics["h#{i}"]?.try(&.to_i64) || 0_i64
      histogram[i] += bucket_val
    end
  end

  ecr("metrics_job")
end

Sidekiq::Filesystem.files.each do |file|
  get(file.path) do |env|
    Sidekiq::Filesystem.serve(file, env)
  end
end

private def retry_or_delete_or_kill(job, params)
  if params["retry"]?
    job.retry!
  elsif params["delete"]?
    job.delete
  elsif params["kill"]?
    job.kill!
  end
end

private def delete_or_add_queue(job, params)
  if params["delete"]?
    job.delete
  elsif params["add_to_queue"]?
    job.add_to_queue
  end
end
