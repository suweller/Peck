require 'set'
require 'thread'

class Peck
  # When a file starts with this path, it's in the Peck library
  PECK_PATH = File.expand_path('..', __FILE__)

  # Matches: `block (2 levels) in <top (required)>'
  ANONYMOUS_BLOCK_RE = /`block/

  def self.clean_backtrace(backtrace)
    stripped = backtrace.dup
    stripped.map! do |line|
      if line.start_with?(PECK_PATH) || line.start_with?("<")
        nil
      elsif line =~ ANONYMOUS_BLOCK_RE
        line.split(':')[0,2].join(':')
      else
        line
      end
    end.compact!
    stripped.empty? ? backtrace : stripped
  end

  PECK_PART_RE = /Peck/
  def self.join_description(description)
    description.map do |part|
      part = part.to_s
      part = nil if part =~ PECK_PART_RE
      part
    end.compact.join(' ')
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
    attr_accessor :ran, :passed, :failed, :errors
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
          backtrace = Peck.clean_backtrace(exception.backtrace)
          puts "\nIn [ #{specification.label} ]:"
          puts "#{backtrace[0]} : #{exception.message}"
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

        @setup.each { |b| context.class_eval(&b) } if @setup

        Peck.contexts << context
        context.class_eval(&block)
        context
      end

      def label
        Peck.join_description(description)
      end

      # Is only ran once for every context when it's initialized. Great place
      # to hook in test suite specific functionality.
      #
      #   Peck::Context.once { |context| context.before { @name = 'Mary' } }
      def once(&block)
        @setup ||= []
        @setup << block
      end

      def before(*args, &block)
        add_callback(@before, *args, &block)
      end
      alias setup before

      def after(*args, &block)
        add_callback(@after, *args, &block)
      end
      alias teardown after

      def it(description, &block)
        return if description !~ Peck.select_specification
        specification = Specification.new(self, @before, @after, description, &block)

        unless block_given?
          specification.errors << Error.new(:missing, "Pending")
        end

        @specifications << specification
        specification
      end

      def describe(*description, &block)
        init(@before, @after, *description, &block)
      end

      private

      def add_callback(chain, *args, &block)
        args.each do |method|
          chain << Proc.new { send(method) }
        end
        if block_given?
          chain << block
        end
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

    def synchronized(&block)
      if semaphore = Thread.current['peck-semaphore']
        semaphore.synchronize(&block)
      else
        block.call
      end
    end

    def run
      if @block
        @before.each { |cb| @context.instance_eval(&cb) }
        synchronized do
          Thread.current['peck-spec'] = self
          @context.instance_eval(&@block)
          Thread.current['peck-spec'] = nil
        end
        Peck.delegates.received_missing(self) if empty?
        @after.each { |cb| @context.instance_eval(&cb) }
      else
        Peck.delegates.received_missing(self)
      end
    rescue Object => e
      Peck.delegates.received_exception(self, e)
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
    #   Peck.delegates << Notifier.new
    attr_reader :delegates

    attr_accessor :concurrency

    def concurrent?
      concurrency && concurrency > 1
    end

    def reset!
      @contexts = []
      @delegates = DelegateSet.new
    end

    def contexts
      @contexts
    end

    def run
      concurrent? ? run_concurrent : run_serial
    end

    def run_at_exit
      unless at_exit_installed
        self.at_exit_installed = true
        delegates << Peck::Reporter.new
        at_exit do
          run
          delegates.at_exit
        end
      end
    end

    def run_serial
      Peck.log("Running specs in serial")
      delegates.started
      Thread.current['peck-semaphore'] = Mutex.new
      contexts.each do |context|
        if context.label =~ select_context
          context.specifications.each do |specification|
            delegates.started_specification(specification)
            specification.run
            delegates.finished_specification(specification)
          end
        end
      end
      delegates.finished
    rescue Exception => e
      log("An error bubbled up from the context, this should never happen and is possibly a bug.")
      raise e
    end

    def all_specifications
      contexts.inject([]) do |all, context|
        all.concat(context.specifications)
      end
    end

    def run_concurrent
      Peck.log("Running specs concurrently")

      delegates.started

      current_spec = -1
      specifications = all_specifications
      threaded do |nr|
        Thread.current['peck-semaphore'] = Mutex.new
        loop do
          spec_index = Thread.exclusive { current_spec += 1 }
          if specification = specifications[spec_index]
            delegates.started_specification(specification)
            specification.run
            delegates.finished_specification(specification)
          else
            break
          end
        end
      end

      delegates.finished
    end

    def threaded
      threads = []
      Peck.concurrency.times do |nr|
        threads[nr] = Thread.new do
          yield nr
        end
      end

      threads.compact.each do |thread|
        begin
          thread.join
        rescue Interrupt
        end
      end
    end
  end

  self.select_context = //
  self.select_specification = //

  reset!
end

module Kernel

  private

  def describe(*description, &block)
    Peck::Context.init([], [], *description, &block)
  end
end