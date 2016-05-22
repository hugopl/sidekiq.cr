# Sidekiq.cr

Sidekiq is a well-regarded background job framework for Ruby.  Now we're
bringing the awesomeness to Crystal, a Ruby-like language.  Why?  To
give you options.  Ruby is friendly and flexible but not terribly fast.
Crystal is statically-typed, compiled and **very fast** but retains a similar syntax to
Ruby.  If you have Ruby jobs which are CPU-intensive or require very high throughput,
you can port them to Crystal and take advantage of the much higher performance.

Rough, initial benchmarks:

Runtime | RSS | Time | Throughput
-----------------------------------
MRI | 50MB | 22 | 4,500 jobs/sec
MRI/hiredis | 50MB | 17 | 7,000 jobs/sec
Crystal 0.17 | 17MB | 6 | 20,000 jobs/sec

# Note

This project is still very unstable.  Do not use except for fun.

## Help wanted

Things that do not exist but I welcome:

* [Data API](/mperham/sidekiq/wiki/API)
* [Testing API](/mperham/sidekiq/wiki/Testing)
* Web UI

See also [the issues](/mperham/sidekiq.cr/issues) for chores and other ideas to help.

Things that do not exist and probably won't ever:

* Support for daemonization, pidfiles, log rotation.
* Delayed extensions

## Compatibility

The Ruby and Crystal versions of Sidekiq **must** remain data compatible in Redis.
Both versions should be able to create and process jobs from each other.
Their APIs **do not** and should not be identical but rather idiomatic to
their respective languages.

## Installation

Add sidekiq.cr to your shards.yml:

```yaml
dependencies:
  sidekiq:
    github: mperham/sidekiq.cr
```

and run `crystal deps`.

## Jobs

A worker class executes jobs.  You create a worker class by including
`Sidekiq::Worker`.  You must define a `perform` method and declare
the types of the arguments using the `perform_types` macro.  **All
arguments to the perform method must be of [JSON::Type](http://crystal-lang.org/api/JSON/Type.html).**

```cr
class SomeWorker
  include Sidekiq::Worker

  perform_types(Int64, String)
  def perform(user_id, email)
  end
end
```

You create a job like so:

```cr
jid = SomeWorker.async.perform(1234_i64, "mike@example.com")
```

Note the difference in syntax to Sidekiq.rb.  It's possible this syntax
will be backported to Ruby.

## Configuration

Because Crystal compiles to a single binary, you need to boot and run
Sidekiq within your code:

```ruby
require "sidekiq"
require "sidekiq/server"
require "your_code"

sidekiq = Sidekiq::Server.new(queues: ["default"], concurrency: 25)
sidekiq.start
sidekiq.monitor # this method never returns
```

## Upgrade

The plan is to eventually have a commercial version for sale, a la Sidekiq Pro and
Enterprise for Ruby.  I have not made any decisions about how this will
be done yet.
