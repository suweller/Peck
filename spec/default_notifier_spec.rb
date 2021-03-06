# encoding: utf-8

require File.expand_path('../preamble', __FILE__)
require 'peck/notifiers/default'
require 'stringio'

describe Peck::Notifiers::Default do
  before do
    @notifier = Peck::Notifiers::Default.new
  end

  it "formats test failures into a readable format" do
    exception = nil
    begin
      raise ArgumentError, "Is a good example of what might happen"
    rescue => e
      exception = e
    end

    spec = FakeSpec.new("Event should go on")
    event = Peck::Event.new(exception, spec)

    capture_stdout do
      @notifier.write_event(2, event)
    end.should.start_with "  2) Event should go on\n\n  Is a good example of what might happen\n\n\tspec/default_notifier_spec.rb"
  end

  it "formats test failures without a message" do
    exception = nil
    begin
      fail
    rescue => e
      exception = e
    end

    spec = FakeSpec.new("Event should go on")
    event = Peck::Event.new(exception, spec)

    capture_stdout do
      @notifier.write_event(2, event)
    end.should.start_with "  2) Event should go on\n\n\tspec/default_notifier_spec.rb"
  end

  it "does not clean backtrace when backtrace cleaning is turned off" do
    Peck.clean_backtrace = false
    begin

      exception = nil
      begin
        fail
      rescue => e
        exception = e
      end

      spec = FakeSpec.new("Event should go on")
      event = Peck::Event.new(exception, spec)

      capture_stdout do
        @notifier.write_event(2, event)
      end.should.include File.expand_path('../../lib/peck', __FILE__)
      
    ensure
      Peck.clean_backtrace = true
    end
  end

  private

  def capture_stdout
    stdout = $stdout
    $stdout = written = StringIO.new('')
    begin
      yield
    ensure
      $stdout = stdout
    end
    written.rewind
    written.read
  end
end
