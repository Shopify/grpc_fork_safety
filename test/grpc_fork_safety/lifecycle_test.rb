# frozen_string_literal: true

require "test_helper"

module GrpcForkSafety
  class FakeGRPC
    attr_reader :events

    def initialize(process)
      @process = process
      @prefork_pid = nil
      @events = []
    end

    def prefork
      if @prefork_pending
        raise "GRPC.prefork already called without a matching GRPC.postfork_{parent,child}"
      end

      @prefork_pending = @process.pid
      @events << :prefork
    end

    def postfork_parent
      unless @prefork_pending
        raise "GRPC::postfork_parent can only be called once following a GRPC::prefork"
      end

      unless @prefork_pending == @process.pid
        raise "GRPC.postfork_parent must be called only from the parent process after a fork"
      end

      @prefork_pending = nil
      @events << :postfork_parent
    end

    def postfork_child
      unless @prefork_pending
        raise "GRPC::postfork_child can only be called once following a GRPC::prefork"
      end

      if @prefork_pending == @process.pid
        raise "GRPC.postfork_child must be called only from the child process after a fork"
      end

      @prefork_pending = nil

      @events << :postfork_child
    end
  end

  class FakeProcess
    attr_accessor :pid

    def initialize(pid)
      @pid = pid
    end
  end

  class TestLifeCycle < Minitest::Test
    def setup
      @process = FakeProcess.new(Process.pid)
      @grpc = FakeGRPC.new(@process)
      @lifecycle = LifeCycle.new(@grpc, @process)
    end

    def test_parent_process_before_after_fork
      @lifecycle.before_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork postfork_parent], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork postfork_parent], @grpc.events
    end

    def test_child_process_before_after_fork
      @lifecycle.before_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      @process.pid += 1

      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events
    end

    def test_parent_process_disable_with_reenable_in_children
      @lifecycle.disable!(reenable_in_children: true)
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      # After fork does nothing in the parent in this mode
      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      # no-op
      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      # fork to child
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events

      # no-op
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events

      @lifecycle.disable!(reenable_in_children: true)
      assert_equal %i[prefork postfork_child prefork], @grpc.events

      # fork another child
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child prefork postfork_child], @grpc.events

      @lifecycle.disable!(reenable_in_children: true)
      assert_equal %i[prefork postfork_child prefork postfork_child prefork], @grpc.events
    end

    def test_parent_process_reenable
      @lifecycle.disable!(reenable_in_children: true)
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      @lifecycle.reenable!

      assert_equal %i[prefork postfork_parent], @grpc.events

      @lifecycle.before_fork
      @process.pid += 1
      @lifecycle.after_fork
      @lifecycle.reenable!

      assert_equal %i[prefork postfork_parent prefork postfork_child], @grpc.events
    end

    def test_before_disable_hook
      called = 0
      @lifecycle.before_disable { called += 1 }

      @lifecycle.before_fork
      assert_equal 1, called

      @lifecycle.before_fork
      assert_equal 1, called
    end

    def test_after_enable_hook_parent
      called_in_parent = 0
      called_in_child = 0
      @lifecycle.after_enable do |in_child|
        if in_child
          called_in_child += 1
        else
          called_in_parent += 1
        end
      end

      assert_equal [0, 0], [called_in_parent, called_in_child]

      # no-op (before_fork wasn't called)
      @lifecycle.after_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.before_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.after_fork
      assert_equal [1, 0], [called_in_parent, called_in_child]

      # no-op (already called)
      @lifecycle.after_fork
      assert_equal [1, 0], [called_in_parent, called_in_child]
    end

    def test_after_enable_hook_child
      called_in_parent = 0
      called_in_child = 0
      @lifecycle.after_enable do |in_child|
        if in_child
          called_in_child += 1
        else
          called_in_parent += 1
        end
      end

      assert_equal [0, 0], [called_in_parent, called_in_child]

      # no-op (before_fork wasn't called)
      @lifecycle.after_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.before_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      # in child process
      @process.pid += 1

      @lifecycle.after_fork
      assert_equal [0, 1], [called_in_parent, called_in_child]

      # no-op (already called)
      @lifecycle.after_fork
      assert_equal [0, 1], [called_in_parent, called_in_child]
    end

    def test_disable_with_reenable_in_children_double_fork
      # parent
      @lifecycle.disable!(reenable_in_children: true)
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      # child
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events

      @lifecycle.before_fork # About to fork grandchild.
      assert_equal %i[prefork postfork_child prefork], @grpc.events

      # grandchild
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child prefork postfork_child], @grpc.events

      # no-op
      @lifecycle.reenable!
      assert_equal %i[prefork postfork_child prefork postfork_child], @grpc.events
    end

    def test_disable_until_explicitly_reenabled_double_fork
      # parent
      @lifecycle.disable!
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      @lifecycle.after_fork # Nothing happens automatically
      assert_equal [:prefork], @grpc.events

      # child
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # About to fork grandchild.
      assert_equal [:prefork], @grpc.events

      # grandchild
      @process.pid += 1
      @lifecycle.after_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.reenable!
      assert_equal %i[prefork postfork_child], @grpc.events
    end

    def test_disable_defaults_to_no_reenable_in_children
      @lifecycle.disable!
      assert_equal [:prefork], @grpc.events

      @process.pid += 1
      @lifecycle.after_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.reenable!
      assert_equal %i[prefork postfork_child], @grpc.events
    end

    def test_keep_disabled_alias_disables_in_parent
      _, stderr = capture_io do
        @lifecycle.keep_disabled!
      end
      assert_match(/keep_disabled!/, stderr)

      assert_equal [:prefork], @grpc.events

      # no-op as it keeps disabled in parent
      @lifecycle.after_fork
      assert_equal [:prefork], @grpc.events
    end

    def test_keep_disabled_alias_reenables_in_children
      _, stderr = capture_io do
        @lifecycle.keep_disabled!
      end
      assert_match(/keep_disabled!/, stderr)

      assert_equal [:prefork], @grpc.events

      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events
    end
  end
end
