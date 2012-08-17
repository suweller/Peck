task :default => :spec

desc "Run all example specs"
task :spec do
  bin_path = File.expand_path('../bin', __FILE__)
  peck = File.join(bin_path, 'peck')
  sh "#{peck} --one-by-one examples"
end

task :test => :spec