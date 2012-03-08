require 'bundler/gem_tasks'

require 'rdoc/task'
RDoc::Task.new do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title = 'big_sitemap'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README*')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test' << Rake.original_dir
  t.pattern = 'test/**/*_test.rb'
  t.verbose = false
end

task :default => :test
