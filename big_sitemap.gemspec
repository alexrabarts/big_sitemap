# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name          = "big_sitemap"
  s.version       = File.read('VERSION').strip
  s.authors       = ["Alex Rabarts", "Tobias Bielohlawek"]
  s.email         = ["alexrabarts@gmail.com", "tobi@soundcloud.com"]
  s.homepage      = %q{http://github.com/alexrabarts/big_sitemap}
  s.summary       = %q{A Sitemap generator specifically designed for large sites (although it works equally well with small sites)}
  s.description   = %q{BigSitemap is a Sitemapgenerator suitable for applications with greater than 50,000 URLs. It splits large Sitemaps into multiple files, gzips the files to minimize bandwidth usage, batches database queries to minimize memory usage, supports increment updates, can be set up with just a few lines of code and is compatible with just about any framework.}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  ["bundler", "shoulda", "mocha", "nokogiri"].each do |gem|
    s.add_development_dependency *gem.split(' ')
  end
end

