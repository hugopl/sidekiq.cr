require "../sidekiq"
require "./api"
require "./web_helpers"

require "kemal"

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
    }

    def self.default_tabs
      DEFAULT_TABS
    end

    def self.custom_tabs
      @@custom_tabs ||= {} of String => String
    end
  end
end

include Sidekiq::Web

public_folder "web"
root_path = ""

private macro crtemplate(xxx)
  render "web/views/#{{{xxx}}}.ecr", "web/views/layout.ecr"
end

get "/busy" do |env|
  crtemplate("busy")
end

post "/busy" do |env|
  if params["identity"]
    p = Sidekiq::Process.new({"identity" => params["identity"]})
    p.quiet! if params[:quiet]
    p.stop! if params[:stop]
  else
    processes.each do |pro|
      pro.quiet! if params[:quiet]
      pro.stop! if params[:stop]
    end
  end
  env.redirect "/busy"
end

get "/queues" do |env|
  @queues = Sidekiq::Queue.all
  crtemplate("queues")
end

get "/queues/:name" do |env|
  halt 404 unless params[:name]
  @count = (params[:count] || 25).to_i
  @name = params[:name]
  @queue = Sidekiq::Queue.new(@name)
  @current_page, @total_size, @messages = page("queue:#{@name}", params[:page], @count)
  @messages = @messages.map { |msg| Sidekiq::JobProxy.new(msg) }
  crtemplate("queue")
end

post "/queues/:name" do |env|
  Sidekiq::Queue.new(params[:name]).clear
  env.redirect "#{root_path}/queues"
end

post "/queues/:name/delete" do |env|
  Sidekiq::JobProxy.new(params[:key_val]).delete
  redirect_with_query("#{root_path}queues/#{params[:name]}")
end

get "/morgue" do |env|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @dead = page("dead", params[:page], @count, reverse: true)
  @dead = @dead.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  crtemplate("morgue")
end

get "/morgue/:key" do |env|
  halt 404 unless params["key"]
  @dead = Sidekiq::DeadSet.new.fetch(*parse_params(params["key"])).first
  env.redirect "#{root_path}morgue" if @dead.nil?
  crtemplate("dead")
end

post "/morgue" do |env|
  env.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
    retry_or_delete_or_kill job, params if job
  end
  redirect_with_query("#{root_path}morgue")
end

post "/morgue/all/delete" do |env|
  Sidekiq::DeadSet.new.clear
  env.redirect "#{root_path}morgue"
end

post "/morgue/all/retry" do |env|
  Sidekiq::DeadSet.new.retry_all
  env.redirect "#{root_path}morgue"
end

post "/morgue/:key" do |env|
  halt 404 unless params["key"]
  job = Sidekiq::DeadSet.new.fetch(*parse_params(params["key"])).first
  retry_or_delete_or_kill job, params if job
  redirect_with_query("#{root_path}morgue")
end


get "/retries" do |env|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @retries = page("retry", params[:page], @count)
  @retries = @retries.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  crtemplate("retries")
end

get "/retries/:key" do |env|
  @retry = Sidekiq::RetrySet.new.fetch(*parse_params(params["key"])).first
  env.redirect "#{root_path}retries" if @retry.nil?
  crtemplate("retry")
end

post "/retries" do |env|
  env.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
    retry_or_delete_or_kill job, params if job
  end
  redirect_with_query("#{root_path}retries")
end

post "/retries/all/delete" do |env|
  Sidekiq::RetrySet.new.clear
  env.redirect "#{root_path}retries"
end

post "/retries/all/retry" do |env|
  Sidekiq::RetrySet.new.retry_all
  env.redirect "#{root_path}retries"
end

post "/retries/:key" do |env|
  job = Sidekiq::RetrySet.new.fetch(*parse_params(params["key"])).first
  retry_or_delete_or_kill job, params if job
  redirect_with_query("#{root_path}retries")
end

get "/scheduled" do |env|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @scheduled = page("schedule", params[:page], @count)
  @scheduled = @scheduled.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  crtemplate("scheduled")
end

get "/scheduled/:key" do |env|
  @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params["key"])).first
  env.redirect "#{root_path}scheduled" if @job.nil?
  crtemplate("scheduled_job_info")
end

post "/scheduled" do |env|
  env.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
    delete_or_add_queue job, params if job
  end
  redirect_with_query("#{root_path}scheduled")
end

post "/scheduled/:key" do |env|
  halt 404 unless params["key"]
  job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params["key"])).first
  delete_or_add_queue job, params if job
  redirect_with_query("#{root_path}scheduled")
end

get "/" do |env|
  @redis_info = redis_info.select{ |k, v| REDIS_KEYS.include? k }
  stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
  @processed_history = stats_history.processed
  @failed_history = stats_history.failed
  crtemplate("dashboard")
end

REDIS_KEYS = %w(redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human)

get "/dashboard/stats" do |env|
  env.redirect "#{root_path}stats"
end

get "/stats" do |env|
  sidekiq_stats = Sidekiq::Stats.new
  redis_stats   = redis_info.select { |k, v| REDIS_KEYS.include? k }

  env.response.content_type = "application/json"
  Hash(String, String) {
    "sidekiq": {
      "processed":       sidekiq_stats.processed,
      "failed":          sidekiq_stats.failed,
      "busy":            sidekiq_stats.workers_size,
      "processes":       sidekiq_stats.processes_size,
      "enqueued":        sidekiq_stats.enqueued,
      "scheduled":       sidekiq_stats.scheduled_size,
      "retries":         sidekiq_stats.retry_size,
      "dead":            sidekiq_stats.dead_size,
      "default_latency": sidekiq_stats.default_queue_latency
    },
    "redis": redis_stats
  }.to_json
end

get "/stats/queues" do |env|
  queue_stats = Sidekiq::Stats::Queues.new

  env.response.content_type = "application/json"
  queue_stats.lengths.to_json
end

private def retry_or_delete_or_kill(job, params)
  if params["retry"]
    job.retry
  elsif params["delete"]
    job.delete
  elsif params["kill"]
    job.kill
  end
end

private def delete_or_add_queue(job, params)
  if params["delete"]
    job.delete
  elsif params["add_to_queue"]
    job.add_to_queue
  end
end
