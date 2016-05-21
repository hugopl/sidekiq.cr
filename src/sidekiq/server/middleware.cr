require "../middleware"

class Sidekiq::Middleware::Logger < Sidekiq::Middleware::Entry
  def call(job, ctx)
    Sidekiq::Logger.with_context("JID=#{job.jid}") do
      ctx.logger.info "Start"
      yield
      ctx.logger.info "Done"
    end
  end
end
