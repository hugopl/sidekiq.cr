require "../middleware"
require "./retry_jobs"

class Sidekiq::Middleware::Logger < Sidekiq::Middleware::ServerEntry
  def call(job, ctx)
    Sidekiq::Logger.with_context("JID=#{job.jid}") do
      a = Time.utc.to_unix_f
      ctx.logger.info { "Start" }
      yield
      ctx.logger.info { "Done: #{"%.6f" % (Time.utc.to_unix_f - a)} sec" }
      true
    end
  end
end
