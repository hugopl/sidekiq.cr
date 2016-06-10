# Sidekiq.cr

Sidekiq is a well-regarded background job framework for Ruby.  Now we're
bringing the awesomeness to Crystal, a Ruby-like language.  Why?  To
give you options.  Ruby is friendly and flexible but not terribly fast.
Crystal is statically-typed, compiled and **very fast** but retains a similar syntax to
Ruby.

Rough, initial benchmarks on OSX 10.11.5:

Runtime | RSS | Time | Throughput
--------|-----|------|-------------
MRI 2.3.0 | 50MB | 21.3 | 4,600 jobs/sec
MRI/hiredis | 55MB | 19.2 | 5,200 jobs/sec
Crystal 0.17 | 18MB | 5.9 | 16,900 jobs/sec

If you have jobs which are CPU-intensive or require very high throughput,
Crystal is an excellent alternative to native Ruby extensions.  It
compiles to a single executable so deployment is much easier than Ruby.

## Getting Started

Please see the [wiki](https://github.com/mperham/sidekiq.cr/wiki) for in-depth documentation and how to get
started using Sidekiq.cr in your own app.

## Upgrade?

If you use and like this project, please [let me
know](mailto:mike@contribsys.com).  If demand warrants, I may port
Sidekiq Pro and Enterprise functionality to Crystal for sale.

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

Mike Perham, http://www.mikeperham.com, [@mperham](https://twitter.com/mperham) / [@sidekiq](https://twitter.com/sidekiq)
