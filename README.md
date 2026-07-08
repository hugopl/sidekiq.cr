# Sidekiq.cr

[![Build Status](https://github.com/hugopl/sidekiq.cr/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/hugopl/sidekiq.cr/actions/workflows/build.yml)

Sidekiq is a well-regarded background job framework for Ruby.  Now we're
bringing the awesomeness to Crystal, a Ruby-like language.  Why?  To
give you options.  Ruby is friendly and flexible but not terribly fast.
Crystal is statically-typed, compiled and **very fast** but retains a similar syntax to
Ruby.

Rough, initial benchmarks on macOS 10.14.5, ruby 2.7.2:

Runtime | RSS | Time | Throughput
--------|-----|------|-------------
Sidekiq 6.2.0 | 55MB | 16.4 | 6,100 jobs/sec
Sidekiq 6.2.0/hiredis | 49MB | 13.0 | 7,900 jobs/sec
Crystal 0.35.1 | 15MB | 3.8 | 26,000 jobs/sec

If you have jobs which are CPU-intensive or require very high throughput,
Crystal is an excellent alternative to native Ruby extensions.  It
compiles to a single executable so deployment is much easier than Ruby.

## Getting Started

Please see the [wiki](https://github.com/hugopl/sidekiq.cr/wiki) for in-depth documentation and how to get
started using Sidekiq.cr in your own app.

## Testing

`require "sidekiq/testing"` in your spec helper to enable `Sidekiq.testing`, which
lets you control how jobs behave when pushed from specs instead of always hitting Redis.

```crystal
require "sidekiq/testing"

Sidekiq.testing(Sidekiq::TestMode::Inline)

HardWorker.async.perform(1_i64)
```

`Sidekiq::TestMode` has two values:

* `Disable` - the default, Sidekiq behaves normally and jobs are pushed to Redis.
* `Inline` - jobs are executed synchronously, in-process, the moment they are
  pushed instead of being enqueued in Redis. It doesn't make sense to use
  `perform_at`/`perform_in` while `Inline` is active, doing so raises an exception.

`Sidekiq.testing` also accepts a block, in which case the mode is only active for the
duration of the block and whatever mode was active before is restored afterwards:

```crystal
Sidekiq.testing(Sidekiq::TestMode::Inline) do
  HardWorker.async.perform(1_i64)
end
```

> [!WARNING]
> `Sidekiq.test_mode` is a single, process-wide flag and mutating it isn't thread-safe.
> Don't run specs that rely on it concurrently across fibers/threads (e.g. with `-Dpreview_mt`
> or a parallel spec runner), or one spec's mode can leak into another's.

## Support

Sidekiq.cr is community-supported and **not** commercially supported by @mperham and Contributed Systems.
General maintenance and bug fixes are always welcomed.

## Help wanted

See [the issues](https://github.com/hugopl/sidekiq.cr/issues) for chores and other ideas to help.

Things that do not exist and probably won't ever:

* Support for daemonization, pidfiles, log rotation - use Upstart/Systemd
* Delayed extensions - too dynamic for Crystal

The Ruby and Crystal versions of Sidekiq **must** remain data compatible in Redis.
Both versions should be able to create and process jobs from each other.
Their APIs **are not** and should not be identical but rather idiomatic to
their respective languages.

## Naming

Sidekiq is a registered trademark of [Contributed Systems](https://sidekiq.org) who has granted use of the name to this project.

## Thanks

Originally developed by Mike Perham, http://www.mikeperham.com. Maintained by Hugo Parente Lima.
