# GrpcForkSafety

Small gem that makes it easier to use the `grpc` gem in a fork safe way.

## Installation

Add the gem to your gemfile **before the `grpc` gem, or any gem that depend on `grpc`:

```ruby
gem "grpc_fork_safety"
gem "grpc"
gem "some-gem-that-depend-on-grpc"
```

## Usage

There isn't anything particular to do, the gem will hook itself into Ruby and properly call the GRPC fork hooks when needed.

### `keep_disabled!`

However, when a process will need to fork repeatedly and won't need to use GRPC, you can optimize by calling `GrpcForkSafety.keep_disabled!`.
`grpc` will be enabled again in child process, but stay shutdown in the current process. This is useful for the main process of Puma or Unicorn
and for the mold process of Pitchfork, e.g.

```ruby
before_fork do
  GrpcForkSafety.keep_disabled!
end
```

If for some reason you need to undo this, you can call `GrpcForkSafety.reenable!`

Additionally, you can ask to keep GRPC disabled until `GrpcForkSafety.reenable!` is called explictly.
This can be useful when using [Pitchfork](https://github.com/Shopify/pitchfork) reforking or similar, as to
keep GRPC disabled in the mold.

```ruby
before_fork do
  GrpcForkSafety.keep_disabled!(reenable_in_child: false)
end
```

### Hooks

You can also register hooks to be called before GRPC is disabled and after it's re-enabled:

```ruby
GrpcForkSafety.before_disable do
  ThreadPool.shutdown
end

GrpcForkSafety.after_enable do |in_child|
  unless in_child
    ThreadPool.start
  end
end
```

Typically if you have background threads using GRPC, you should make sure to shut them down in `before_disable`.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/grpc_fork_safety.
