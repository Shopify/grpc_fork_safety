# frozen_string_literal: true

require_relative "init"

module GrpcForkSafety
  Error = Class.new(StandardError)
  DEPRECATED_KEEP_DISABLED_MESSAGE =
    "DEPRECATION WARNING: `keep_disabled!` is deprecated. " \
    "Use `disable!(reenable_in_children: true)`."
  DEPRECATED_KEEP_DISABLED_PREDICATE_MESSAGE =
    "DEPRECATION WARNING: `keep_disabled?` is deprecated and may be removed in a future major release."

  class BaseLifeCycle
    def initialize
      # Default behavior (without calling disable!) is to automatically
      # disable at fork and then reenable in both parent and children.
      @reenable_in_parent = true
      @reenable_in_children = true
    end

    def disable!(reenable_in_children: false)
      @reenable_in_parent = false
      @reenable_in_children = reenable_in_children
      before_fork
    end

    # Deprecated method that disabled in the parent but reenabled in children.
    def keep_disabled!
      warn_deprecated_keep_disabled!
      disable!(reenable_in_children: true)
    end

    # Deprecated method originally paired with keep_disabled!.
    def keep_disabled?
      warn_deprecated_keep_disabled_predicate!
      !@reenable_in_parent
    end

    def reenable!
      @reenable_in_parent = true
      @reenable_in_children = true
      after_fork
    end

    private

    def warn_deprecated_keep_disabled!
      return if @keep_disabled_warned

      warn DEPRECATED_KEEP_DISABLED_MESSAGE
      @keep_disabled_warned = true
    end

    def warn_deprecated_keep_disabled_predicate!
      return if @keep_disabled_predicate_warned

      warn DEPRECATED_KEEP_DISABLED_PREDICATE_MESSAGE
      @keep_disabled_predicate_warned = true
    end
  end

  class LifeCycle < BaseLifeCycle
    def initialize(grpc = ::GRPC, process = ::Process)
      super()
      @grpc = grpc
      @process = process
      @shutdown_by = nil
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
        if @reenable_in_parent
          @grpc.postfork_parent
          @shutdown_by = nil

          @after_enable.each do |cb|
            cb.call(false)
          end
        end
      elsif @reenable_in_children
        @shutdown_by = nil
        @grpc.postfork_child
        @after_enable.each do |cb|
          cb.call(true)
        end
      end
    end
  end

  class NoopLifeCycle < BaseLifeCycle
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
    def disable!(reenable_in_children: false)
      @lifecycle.disable!(reenable_in_children:)
    end

    def keep_disabled!
      @lifecycle.keep_disabled!
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
