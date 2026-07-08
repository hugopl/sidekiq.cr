require "../sidekiq"

# #
# Require "sidekiq/testing" in your spec_helper (or similar) to enable
# `Sidekiq.testing`.  This monkey patches `Sidekiq::Client` so jobs
# pushed while `Sidekiq::TestMode::Inline` is active don't hit Redis
# at all, they run synchronously instead.
#
#   require "sidekiq/testing"
#
#   Sidekiq.testing(Sidekiq::TestMode::Inline)
#
module Sidekiq
  # #
  # Disable - the default. Sidekiq behaves normally: jobs are pushed to Redis.
  # Inline  - jobs are executed synchronously, in-process, the moment
  #           they are pushed instead of being enqueued in Redis.
  enum TestMode
    Disable
    Inline
  end

  class_property test_mode : Sidekiq::TestMode = Sidekiq::TestMode::Disable

  # #
  # Sets the Sidekiq test mode globally, until changed again.
  #
  #   Sidekiq.testing(Sidekiq::TestMode::Inline)
  #
  def self.testing(mode : Sidekiq::TestMode) : Nil
    self.test_mode = mode
  end

  # #
  # Sets the Sidekiq test mode for the duration of the block, restoring
  # whatever mode was previously active once the block returns.
  #
  #   Sidekiq.testing(Sidekiq::TestMode::Inline) do
  #     HardWorker.async.perform(1_i64)
  #   end
  #
  def self.testing(mode : Sidekiq::TestMode, &)
    previous_mode = test_mode
    self.test_mode = mode
    begin
      yield
    ensure
      self.test_mode = previous_mode
    end
  end

  class Client
    def push(job : Sidekiq::Job)
      return previous_def if Sidekiq.test_mode.disable?

      if job.at
        raise "Sidekiq.testing(Inline) does not make sense with perform_at/perform_in: " \
              "#{job.klass} was scheduled for #{job.at}, but inline mode always runs jobs immediately"
      end

      result = middleware.invoke(job, @ctx) { true }
      return nil unless result

      # `execute` relies on `Job.@@jobtypes`, a class variable that Crystal
      # scopes per-subclass rather than sharing across the hierarchy (unlike
      # Ruby). `job` here is a Worker-specific `PerformProxy < Job`, so it
      # must be round-tripped through JSON into a plain `Job` first, exactly
      # like the real Redis-backed path does.
      Sidekiq::Job.from_json(job.to_json).execute(@ctx)
      job.jid
    end

    def push_bulk(job : Sidekiq::Job, allargs : Array(String))
      return previous_def if Sidekiq.test_mode.disable?

      payloads = build_bulk_payloads(job, allargs)

      # Unlike `push`, `copy` here is already a plain `Sidekiq::Job` (built
      # via `Sidekiq::Job.new` in `build_bulk_payloads`), not a Worker-specific
      # `PerformProxy`, so it can be executed directly without a JSON round-trip.
      payloads.each(&.execute(@ctx))
      payloads.map(&.jid)
    end
  end
end
