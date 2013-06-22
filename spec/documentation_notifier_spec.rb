# encoding: utf-8

require File.expand_path('../preamble', __FILE__)
require 'stringio'

require 'peck/notifiers/documentation'

class Fake
  def initialize(attributes={})
    attributes.each do |key, value|
      send(key.to_s + '=', value)
    end
  end
end

class FakeDocContext < Fake
  attr_accessor :label
end

class FakeDocSpec < Fake
  attr_writer :label
  attr_accessor :description, :context
  attr_accessor :expectations, :events

  def label
    context ? "#{@context.label} #{@description}" : @label
  end

  def passed?
    true
  end
end

describe Peck::Notifiers::Documentation do
  before do
    @notifier = Peck::Notifiers::Documentation.new
  end

  it "formats test failures into a readable format" do
    exception = nil
    begin
      raise ArgumentError, "Is a good example of what might happen"
    rescue => e
      exception = e
    end

    spec = FakeDocSpec.new(:label => "Event should go on")
    event = Peck::Event.new(exception, spec)

    capture_stdout do
      @notifier.write_event(2, event)
    end.should == "  \e[31m2) Event should go on\e[0m\n\n  Is a good example of what might happen\n\n\tspec/documentation_notifier_spec.rb:42\n\n"
  end

  it "formats test failures without a message" do
    exception = nil
    begin
      fail
    rescue => e
      exception = e
    end

    spec = FakeDocSpec.new(:label => "Event should go on")
    event = Peck::Event.new(exception, spec)

    capture_stdout do
      @notifier.write_event(2, event)
    end.should == "  \e[31m2) Event should go on\e[0m\n\n\tspec/documentation_notifier_spec.rb:58\n\n"
  end

  it "formats successful specs" do
    context = FakeDocContext.new(
      :label => 'Author'
    )
    spec = FakeDocSpec.new(
      :description => "allows books to be read",
      :context => context
    )
    capture_stdout do
      @notifier.finished_specification(spec)
    end.should == "\nAuthor\n\n [\e[32mx\e[0m] allows books to be read\n"
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