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

    def test_parent_process_keep_disabled
      @lifecycle.keep_disabled!
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events
      assert_predicate @lifecycle, :keep_disabled?
    end

    def test_child_process_keep_disabled
      @lifecycle.before_fork
      assert_equal [:prefork], @grpc.events

      @process.pid += 1

      @lifecycle.after_fork
      assert_equal %i[prefork postfork_child], @grpc.events
      refute_predicate @lifecycle, :keep_disabled?
    end

    def test_parent_process_reenable
      @lifecycle.keep_disabled!
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events
      assert_predicate @lifecycle, :keep_disabled?

      @lifecycle.reenable!

      assert_equal %i[prefork postfork_parent], @grpc.events
      refute_predicate @lifecycle, :keep_disabled?

      @lifecycle.before_fork
      @process.pid += 1
      @lifecycle.after_fork
      @lifecycle.reenable!

      assert_equal %i[prefork postfork_parent prefork postfork_child], @grpc.events
      refute_predicate @lifecycle, :keep_disabled?
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

      @lifecycle.after_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.before_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.after_fork
      assert_equal [1, 0], [called_in_parent, called_in_child]

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

      @lifecycle.after_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @lifecycle.before_fork
      assert_equal [0, 0], [called_in_parent, called_in_child]

      @process.pid += 1

      @lifecycle.after_fork
      assert_equal [0, 1], [called_in_parent, called_in_child]

      @lifecycle.after_fork
      assert_equal [0, 1], [called_in_parent, called_in_child]
    end

    def test_keep_disabled_in_children
      @lifecycle.keep_disabled_in_children!
      assert_equal [], @grpc.events

      @lifecycle.before_fork
      assert_equal [:prefork], @grpc.events

      @lifecycle.before_fork # Repeated call is a noop
      assert_equal [:prefork], @grpc.events

      assert_predicate @lifecycle, :keep_disabled_in_children?
      refute_predicate @lifecycle, :keep_disabled?

      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      assert_predicate @lifecycle, :keep_disabled_in_children?
      assert_predicate @lifecycle, :keep_disabled?

      @process.pid += 1
      @lifecycle.after_fork
      assert_equal %i[prefork], @grpc.events

      assert_predicate @lifecycle, :keep_disabled_in_children?
      assert_predicate @lifecycle, :keep_disabled?

      @lifecycle.reenable!
      refute_predicate @lifecycle, :keep_disabled_in_children?
      refute_predicate @lifecycle, :keep_disabled?
      assert_equal %i[prefork postfork_child], @grpc.events
    end
  end
end
