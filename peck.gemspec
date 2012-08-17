# encoding: utf-8

$:.unshift File.expand_path('../lib', __FILE__)
require 'peck'

Gem::Specification.new do |s|
  s.name            = "peck"
  s.version         = Peck::VERSION
  s.date            = Date.today

  s.platform        = Gem::Platform::RUBY
  s.summary         = "A concurrent spec framework."

  s.description = <<-EOF
Peck is a small spec framework made for concurrency.

It borrows a lot of code and legacy from Bacon and MacBacon.
  EOF

  s.files           = Dir['lib/**/*.rb', 'bin/peck', 'README.md', 'LICENSE']
  s.bindir          = 'bin'
  s.executables     << 'peck'
  s.require_path    = 'lib'
  s.has_rdoc        = true
  # s.extra_rdoc_files = ['README.md']
  s.test_files      = []

  s.authors  = ["Christian Neukirchen", "Eloy Durán", "Manfred Stienstra"]
  s.homepage = "http://github.com/Fingertips/Peck"
  s.email    = %w{ manfred@fngtps.com }
end