# frozen_string_literal: true

require "grpc_fork_safety/no_patch"

module GrpcForkSafety
  module ProcessExtension
    def _fork
      GrpcForkSafety._before_fork_hook
      pid = super
      GrpcForkSafety._after_fork_hook
      pid
    end
  end

  class << self
    def patch!
      ::Process.singleton_class.prepend(ProcessExtension)
    end
  end
end
