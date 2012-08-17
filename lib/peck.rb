# encoding: utf-8

require 'peck/base'
require 'peck/expectations'

class Peck
  VERSION = "1.0"

  def self.log(message)
    $stderr.puts("{!} #{message}") if $DEBUG
  end
end