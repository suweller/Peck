# encoding: utf-8

require 'peck'
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

Peck.run_at_exit