# encoding: utf-8

require 'set'
require 'thread'

class Lardon
  VERSION = "1.0"

  def self.log(message)
    $stderr.puts("{!} #{message}") if $DEBUG
  end

  def self.trim_backtrace(backtrace)
    backtrace.select do |line|
      !line.start_with?(__FILE__)
    end
  end

  class DelegateSet < Set
    MESSAGES_RE = /^(started|finished|received|at_exit)/

    def method_missing(method, *args, &block)
      if method.to_s =~ MESSAGES_RE
        each do |delegate|
          if delegate.respond_to?(method)
            delegate.send(method, *args, &block)
          end
        end
      end
    end
  end

  class Reporter
    def initialize
      @ran = @passed = @failed = @errors = 0
      @exceptions = []
      @missing = []
      $stdout.sync = true
    end

    def started
      puts "Started."
      @started_at = Time.now
    end

    def finished
      @finished_at = Time.now
    end

    def received_missing(specification)
      @missing << specification
    end

    def received_exception(specification, exception)
      @exceptions << [specification, exception]
    end

    def finished_specification(specification)
      @ran += 1
      if specification.error?
        @errors += 1
        $stdout.write('e')
      elsif specification.empty?
        $stdout.write('m')
      elsif specification.passed?
        @passed += 1
        $stdout.write('.')
      elsif specification.failure?
        @failed += 1
        $stdout.write('f')
      end
    end

    def runtime_in_seconds
      runtime = @finished_at - @started_at
      (runtime * 100).round / 100.0
    end

    def write_missing
      unless @missing.empty?
        puts "Unimplemented specs:\n\n"
        @missing.each do |specification|
          puts "- #{specification.label}"
        end
        puts
      end
    end

    def write_exceptions
      unless @exceptions.empty?
        @exceptions.each do |specification, exception|
          backtrace = Lardon.trim_backtrace(exception.backtrace)
          puts "\nIn [ #{specification.label} ]:"
          puts "#{strip_anonymous_block(backtrace[0])} : #{exception.message}"
          if backtrace.length > 1
            puts "#{backtrace[1..-1].join("\n\t")}"
          end
        end
      end
    end
    
    def write_stats
      puts "Finished in #{runtime_in_seconds} seconds.\n\n"
      puts "#{@ran} #{pluralize(@ran, 'spec')}, #{@failed} #{pluralize(@failed, 'failure')}, #{@errors} #{pluralize(@errors, 'error')}"
    end

    def at_exit
      puts if @ran > 0
      write_exceptions
      puts unless @exceptions.empty?
      write_missing
      write_stats
    end

    private

    # Matches: `block (2 levels) in <top (required)>'
    ANONYMOUS_BLOCK_RE = /`block/

    def strip_anonymous_block(line)
      if line =~ ANONYMOUS_BLOCK_RE
        line.split(':')[0,2].join(':')
      else
        line
      end
    end

    def pluralize(count, stem)
      count == 1 ? stem : "#{stem}s"
    end
  end

  class Context
    attr_reader :specification

    def initialize(specification)
      @specification = specification
    end

    def describe(*args, &block)
      self.class.describe(*args, &block)
    end

    class << self
      FILENAME_WITHOUT_LINE_RE = /^(.+?):\d+/

      attr_reader :description, :block, :specifications, :source_file
      attr_accessor :timeout

      def init(before, after, *description, &block)
        # Find the first file in the backtrace which is not this file
        if source_file = caller.find { |line| line[0,__FILE__.size] != __FILE__ }
          source_file = File.expand_path(source_file.match(FILENAME_WITHOUT_LINE_RE)[1])
        else
          log("Unable to determine the file in which the context is defined.")
        end

        context = Class.new(self) do
          @before = before.dup
          @after = after.dup
          @description = description
          @block = block
          @specifications = []
          @source_file = source_file
          @timeout = 10 # seconds
        end

        Lardon.contexts << context
        context.class_eval(&block)
        context
      end

      def label
        description.map(&:to_s).join(' ')
      end

      def before(&block)
        @before << block
      end

      def after(&block)
        @after << block
      end

      def it(description, &block)
        return if description !~ Lardon.select_specification
        specification = Specification.new(self, @before, @after, description, &block)

        unless block_given?
          specification.errors << Error.new(:missing, "Pending")
        end

        @specifications << specification
        specification
      end

      def pending(description)
        spec = Specification.new(self, @before, @after, description, &block)
        @specifications << spec
        spec
      end

      def describe(*description, &block)
        init_context(@before, @after, *description, &block)
      end
    end
  end

  class Error < RuntimeError
    attr_accessor :type

    def initialize(type, message)
      @type = type.to_s
      super message
    end

    def count_as?(type)
      @type == type.to_s
    end
  end

  class Specification
    attr_reader :description, :context
    attr_accessor :expectations, :errors

    def initialize(context, before, after, description, &block)
      @context = context.new(self)
      @before = before.dup
      @after = after.dup
      @description = description
      @block = block

      @expectations = []
      @errors = []

      @finished = false
    end

    def run
      if @block
        @before.each { |cb| @context.instance_eval(&cb) }
        Thread.current['peck-semaphore'].synchronize do
          Thread.current['peck-spec'] = self
          @context.instance_eval(&@block)
          Thread.current['peck-spec'] = nil
        end
        Lardon.delegates.received_missing(self) if empty?
        @after.each { |cb| @context.instance_eval(&cb) }
      else
        Lardon.delegates.received_missing(self)
      end
    rescue Object => e
      Lardon.delegates.received_exception(self, e)
      @exception = e
    ensure
      @finished = true
    end

    def label
      "#{@context.class.label} #{@description}"
    end

    def empty?
      @expectations.empty?
    end

    def error?
      !@exception.nil?
    end

    def passed?
      @errors.empty?
    end

    def failure?
      !passed?
    end
  end

  class << self
    attr_accessor :at_exit_installed

    # Used to select which contexts and specs should be run
    attr_accessor :select_context, :select_specification

    attr_accessor :backtraces

    # This can be used by a `client' to receive status updates.
    #
    #   Lardon.delegates << Notifier.new
    attr_reader :delegates

    attr_accessor :concurrent
    alias_method  :concurrent?, :concurrent

    def reset!
      @contexts = []
      @delegates = DelegateSet.new
    end

    def contexts
      @contexts
    end

    def run
      delegates.started
      concurrent? ? run_concurrent : run_serial
      delegates.finished
    end

    def run_at_exit
      unless at_exit_installed
        self.at_exit_installed = true
        delegates << Lardon::Reporter.new
        at_exit do
          run
          delegates.at_exit
        end
      end
    end

    def run_serial
      Thread.current['peck-semaphore'] = Mutex.new
      contexts.each do |context|
        if context.label =~ select_context
          delegates.started_context(context)
          context.specifications.each do |specification|
            delegates.started_specification(specification)
            specification.run
            delegates.finished_specification(specification)
          end
          delegates.finished_context(context)
        end
      end
    rescue Exception => e
      log("An error bubbled up from the context, this should never happen and is possibly a bug.")
      raise e
    end

    def run_concurrent
    end
  end

  self.select_context = //
  self.select_specification = //

  reset!
end

module Kernel

  private

  def describe(*description, &block)
    Lardon::Context.init([], [], *description, &block)
  end
end