require "benchmark"
require "../middleware"
require "./retry_jobs"

class Sidekiq::Middleware::Logger < Sidekiq::Middleware::ServerEntry
  def call(job, ctx) : Bool
    ctx.logger.info &.emit("Start", jid: job.jid)
    time = Benchmark.realtime { yield }.to_f.format(decimal_places: 6)
    ctx.logger.info &.emit("Done: #{time} sec", JID: job.jid)
    true
  end
end
