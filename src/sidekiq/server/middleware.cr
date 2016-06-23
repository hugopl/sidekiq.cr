require "../middleware"
require "./retry_jobs"

class Sidekiq::Middleware::Logger < Sidekiq::Middleware::ServerEntry
  def call(job, ctx)
    Sidekiq::Logger.with_context("JID=#{job.jid}") do
      a = Time.now.epoch_f
      ctx.logger.info { "Start" }
      yield
      ctx.logger.info { "Done: #{"%.6f" % (Time.now.epoch_f - a)} sec" }
      true
    end
  end
end
