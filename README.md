# Sidekiq.cr

[![Build Status](https://github.com/mperham/sidekiq.cr/actions/workflows/build.yml/badge.svg?branch=master)](https://github.com/mperham/sidekiq.cr/actions/workflows/build.yml)

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

Please see the [wiki](https://github.com/mperham/sidekiq.cr/wiki) for in-depth documentation and how to get
started using Sidekiq.cr in your own app.

## Support

Sidekiq.cr is community-supported and **not** commercially supported by @mperham and Contributed Systems.
General maintenance and bug fixes are always welcomed.

## Help wanted

See [the issues](https://github.com/mperham/sidekiq.cr/issues) for chores and other ideas to help.

Things that do not exist and probably won't ever:

* Support for daemonization, pidfiles, log rotation - use Upstart/Systemd
* Delayed extensions - too dynamic for Crystal

The Ruby and Crystal versions of Sidekiq **must** remain data compatible in Redis.
Both versions should be able to create and process jobs from each other.
Their APIs **are not** and should not be identical but rather idiomatic to
their respective languages.

## Author

Mike Perham, http://www.mikeperham.com, [@getajobmike](https://twitter.com/getajobmike) / [@sidekiq](https://twitter.com/sidekiq)
