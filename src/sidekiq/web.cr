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

class HTTP::Server::Context
  include Sidekiq::WebHelpers
end

public_folder "web"
root_path = ""

macro ecr(xxx)
  render "#{{{__DIR__}}}/../../web/views/#{{{xxx}}}.ecr", "#{{{__DIR__}}}/../../web/views/layout.ecr"
end

get "/busy" do |x|
  ecr("busy")
end

post "/busy" do |x|
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
  x.redirect "/busy"
end

get "/queues" do |x|
  @queues = Sidekiq::Queue.all
  ecr("queues")
end

get "/queues/:name" do |x|
  halt 404 unless params[:name]
  @count = (params[:count] || 25).to_i
  @name = params[:name]
  @queue = Sidekiq::Queue.new(@name)
  @current_page, @total_size, @messages = page("queue:#{@name}", params[:page], @count)
  @messages = @messages.map { |msg| Sidekiq::JobProxy.new(msg) }
  ecr("queue")
end

post "/queues/:name" do |x|
  Sidekiq::Queue.new(params[:name]).clear
  x.redirect "#{root_path}/queues"
end

post "/queues/:name/delete" do |x|
  Sidekiq::JobProxy.new(params[:key_val]).delete
  redirect_with_query("#{root_path}queues/#{params[:name]}")
end

get "/morgue" do |x|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @dead = page("dead", params[:page], @count, reverse: true)
  @dead = @dead.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  ecr("morgue")
end

get "/morgue/:key" do |x|
  halt 404 unless params["key"]
  @dead = Sidekiq::DeadSet.new.fetch(*parse_params(params["key"])).first
  x.redirect "#{root_path}morgue" if @dead.nil?
  ecr("dead")
end

post "/morgue" do |x|
  x.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::DeadSet.new.fetch(*parse_params(key)).first
    retry_or_delete_or_kill job, params if job
  end
  redirect_with_query("#{root_path}morgue")
end

post "/morgue/all/delete" do |x|
  Sidekiq::DeadSet.new.clear
  x.redirect "#{root_path}morgue"
end

post "/morgue/all/retry" do |x|
  Sidekiq::DeadSet.new.retry_all
  x.redirect "#{root_path}morgue"
end

post "/morgue/:key" do |x|
  halt 404 unless params["key"]
  job = Sidekiq::DeadSet.new.fetch(*parse_params(params["key"])).first
  retry_or_delete_or_kill job, params if job
  redirect_with_query("#{root_path}morgue")
end


get "/retries" do |x|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @retries = page("retry", params[:page], @count)
  @retries = @retries.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  ecr("retries")
end

get "/retries/:key" do |x|
  @retry = Sidekiq::RetrySet.new.fetch(*parse_params(params["key"])).first
  x.redirect "#{root_path}retries" if @retry.nil?
  ecr("retry")
end

post "/retries" do |x|
  x.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::RetrySet.new.fetch(*parse_params(key)).first
    retry_or_delete_or_kill job, params if job
  end
  redirect_with_query("#{root_path}retries")
end

post "/retries/all/delete" do |x|
  Sidekiq::RetrySet.new.clear
  x.redirect "#{root_path}retries"
end

post "/retries/all/retry" do |x|
  Sidekiq::RetrySet.new.retry_all
  x.redirect "#{root_path}retries"
end

post "/retries/:key" do |x|
  job = Sidekiq::RetrySet.new.fetch(*parse_params(params["key"])).first
  retry_or_delete_or_kill job, params if job
  redirect_with_query("#{root_path}retries")
end

get "/scheduled" do |x|
  @count = (params[:count] || 25).to_i
  @current_page, @total_size, @scheduled = page("schedule", params[:page], @count)
  @scheduled = @scheduled.map { |msg, score| Sidekiq::SortedEntry.new(nil, score, msg) }
  ecr("scheduled")
end

get "/scheduled/:key" do |x|
  @job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params["key"])).first
  x.redirect "#{root_path}scheduled" if @job.nil?
  ecr("scheduled_job_info")
end

post "/scheduled" do |x|
  x.redirect request.path unless params["key"]

  params["key"].each do |key|
    job = Sidekiq::ScheduledSet.new.fetch(*parse_params(key)).first
    delete_or_add_queue job, params if job
  end
  redirect_with_query("#{root_path}scheduled")
end

post "/scheduled/:key" do |x|
  halt 404 unless params["key"]
  job = Sidekiq::ScheduledSet.new.fetch(*parse_params(params["key"])).first
  delete_or_add_queue job, params if job
  redirect_with_query("#{root_path}scheduled")
end

get "/" do |x|
  @redis_info = redis_info.select{ |k, v| REDIS_KEYS.include? k }
  stats_history = Sidekiq::Stats::History.new((params[:days] || 30).to_i)
  @processed_history = stats_history.processed
  @failed_history = stats_history.failed
  ecr("dashboard")
end

REDIS_KEYS = %w(redis_version uptime_in_days connected_clients used_memory_human used_memory_peak_human)

get "/dashboard/stats" do |x|
  x.redirect "#{root_path}stats"
end

get "/stats" do |x|
  sidekiq_stats = Sidekiq::Stats.new
  redis_stats   = redis_info.select { |k, v| REDIS_KEYS.include? k }

  x.response.content_type = "application/json"
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

get "/stats/queues" do |x|
  queue_stats = Sidekiq::Stats::Queues.new

  x.response.content_type = "application/json"
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
