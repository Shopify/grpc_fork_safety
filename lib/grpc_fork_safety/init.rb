# frozen_string_literal: true

require_relative "version"

if defined? GRPC::Core # ::GRPC may be loaded by bundler from `grpc.gemspec` so we check `GRPC::Core`
  raise <<~ERROR
    GRPC was loaded before `grpc_fork_safety` preventing to enable fork support

    You may need to set `require: false` in your Gemfile where `grpc` is listed or
    move `gem "grpc_fork_safety"` before `gem "grpc"`in your Gemfile.
  ERROR
end

ENV["GRPC_ENABLE_FORK_SUPPORT"] = "1"
require "grpc"
