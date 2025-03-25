# frozen_string_literal: true

require "grpc_fork_safety/init"

module GrpcForkSafety
  Error = Class.new(StandardError)

  class LifeCycle
    def initialize(grpc = ::GRPC, process = ::Process)
      @grpc = grpc
      @process = process
      @shutdown_by = nil
      @keep_disabled = false
      @reenable_in_child = true
      @before_disable = []
      @after_enable = []
    end

    def before_disable(&block)
      raise Error, "No block given" unless block_given?

      @before_disable << block
    end

    def after_enable(&block)
      raise Error, "No block given" unless block_given?

      @after_enable << block
    end

    def keep_disabled!(reenable_in_child: true)
      @keep_disabled = true
      @reenable_in_child = reenable_in_child
      before_fork
    end

    def keep_disabled?
      @keep_disabled
    end

    def reenable_in_child?
      @reenable_in_child
    end

    def reenable!
      @keep_disabled = false
      @reenable_in_child = true
      after_fork
    end

    def before_fork
      return if @shutdown_by

      @before_disable.each(&:call)

      @grpc.prefork
      @shutdown_by = @process.pid
    end

    def after_fork
      if @shutdown_by.nil?
        # noop
      elsif @shutdown_by == @process.pid # In parent
        unless @keep_disabled
          @grpc.postfork_parent
          @shutdown_by = nil

          @after_enable.each do |cb|
            cb.call(false)
          end
        end
      elsif @reenable_in_child
        @keep_disabled = false
        @shutdown_by = nil
        @grpc.postfork_child
        @after_enable.each do |cb|
          cb.call(true)
        end
      end
    end
  end

  class NoopLifeCycle
    def initialize
      @keep_disabled = false
      @reenable_in_child = true
    end

    def keep_disabled!(reenable_in_child: true)
      @keep_disabled = true
      @reenable_in_child = reenable_in_child
    end

    def keep_disabled?
      @keep_disabled
    end

    def reenable!
      @keep_disabled = false
    end

    def before_fork; end

    def after_fork; end

    def before_disable; end

    def after_enable; end
  end

  GRPC_FORK_SUPPORT = RUBY_PLATFORM.match?(/linux/i)

  @lifecycle = if GRPC_FORK_SUPPORT
                 LifeCycle.new
               else
                 NoopLifeCycle.new
               end

  class << self
    def keep_disabled!(reenable_in_child: true)
      @lifecycle.keep_disabled!(reenable_in_child: reenable_in_child)
    end

    def reenable!
      @lifecycle.reenable!
    end

    def before_disable(&)
      @lifecycle.before_disable(&)
    end

    def after_enable(&)
      @lifecycle.after_enable(&)
    end

    def _before_fork_hook
      @lifecycle.before_fork
    end

    def _after_fork_hook
      @lifecycle.after_fork
    end
  end
end
