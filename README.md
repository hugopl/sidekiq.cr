# Sidekiq for Crystal, sidekiq.cr

Sidekiq is a well-regarded background job framework for Ruby.  Now we're
bringing the awesomeness to Crystal, a Ruby-like language.  Why?  To
give you options.  Ruby is friendly and flexible but not terribly fast.
Crystal is statically-typed, compiled and **very fast** but retains a similar syntax to
Ruby.  If you have Ruby jobs which are CPU-intensive, you can port them to
Crystal and take advantage of Crystal's much higher performance.

## Installation

Add sidekiq.cr to your shards.yml:

```yaml
dependencies:
  sidekiq:
    github: mperham/sidekiq.cr
```

and run `crystal deps`.

## Configuration

Because Crystal compiles to a single binary, you need to boot and run
Sidekiq within your code:

```ruby
require "sidekiq"
require "your_code"

sidekiq = Sidekiq.new
sidekiq.run_server
```

Note that the `run_server` method never returns.
