# encoding: utf-8

require 'peck'
Peck.concurrency = 9

describe Peck do
  100.times do
    it "works with slow specs" do
      sleep 0.5
      1.should == 1
    end
  end
end

Peck.run_at_exit