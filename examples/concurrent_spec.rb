# encoding: utf-8

require 'peck/base'
require 'peck/expectations'

Peck.concurrency = 9

describe Peck do
  100.times do
    it "runs concurrently" do
      1.should == 1
    end

    it "runs concurrently with multiple specs" do
      2.should == 2
    end
  end
end

def assert(success, where=0)
  unless success
    puts [
      "Assertion failed:",
      caller[0].split(":")[0,2].join(':')
    ].join("\n  ")
  end
end

reporter = Peck::Reporter.new
Peck.delegates << reporter
Peck.run
puts
assert(reporter.ran == 200)
assert(reporter.passed == 200)
assert(reporter.failed == 0)
assert(reporter.errors == 0)