# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "grpc_fork_safety/no_patch"

require "minitest/autorun"
