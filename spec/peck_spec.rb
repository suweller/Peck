# encoding: utf-8

require File.expand_path('../spec_helper', __FILE__)

describe Peck::Specification do
  it "reports about an implemented spec"

  it "reports on method missing exceptions" do
    unknown_methods
  end

  it "reports on flunks" do
    flunk "Not quite right"
  end

  it "runs failing expectations" do
    1.should == 2
  end

  it "runs successful expectations" do
    2.should == 2
  end
end
