require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "big_sitemap"
    s.summary = %Q{A Sitemap generator specifically designed for large sites (although it works equally well with small sites)}
    s.email = %w(alexrabarts@gmail.com tobi@soundcloud.com)
    s.homepage = "http://github.com/alexrabarts/big_sitemap"
    s.description = "A Sitemap generator specifically designed for large sites (although it works equally well with small sites)"
    s.authors = ["Alex Rabarts", "Tobias Bielohlawek"]
    s.add_dependency 'bundler'
  end
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

require 'rake/rdoctask'
Rake::RDocTask.new do |rdoc|
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
