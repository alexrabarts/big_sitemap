# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{big_sitemap}
  s.version = "0.2.0"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Alex Rabarts"]
  s.date = %q{2009-03-11}
  s.description = %q{A Sitemap generator specifically designed for large sites (although it works equally well with small sites)}
  s.email = %q{alexrabarts@gmail.com}
  s.files = ["History.txt", "README.markdown", "VERSION.yml", "lib/big_sitemap.rb", "test/big_sitemap_test.rb", "test/fixtures", "test/fixtures/test_model.rb", "test/test_helper.rb"]
  s.has_rdoc = true
  s.homepage = %q{http://github.com/alexrabarts/big_sitemap}
  s.rdoc_options = ["--inline-source", "--charset=UTF-8"]
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.1}
  s.summary = %q{A Sitemap generator specifically designed for large sites (although it works equally well with small sites)}

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 2

    if Gem::Version.new(Gem::RubyGemsVersion) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<builder>, [">= 2.1.2"])
      s.add_runtime_dependency(%q<extlib>, [">= 0.9.9"])
    else
      s.add_dependency(%q<builder>, [">= 2.1.2"])
      s.add_dependency(%q<extlib>, [">= 0.9.9"])
    end
  else
    s.add_dependency(%q<builder>, [">= 2.1.2"])
    s.add_dependency(%q<extlib>, [">= 0.9.9"])
  end
end
