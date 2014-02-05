require 'rubygems'
require 'bundler/setup'

require 'test/unit'
require 'shoulda'
require 'mocha'
require File.expand_path('fixtures/test_model')

require 'big_sitemap'

class Test::Unit::TestCase

  #TestHelper
  private
  def generate_sitemap(options={}, &block)
    BigSitemap.generate(options.merge(:base_url => 'http://example.com', :document_root => tmp_dir), &block)
  end

  def delete_tmp_files
    Dir["#{sitemaps_dir}/sitemap*"].each do |f|
      FileUtils.rm_rf f
    end
  end

  def sitemaps_index_file
    "#{unzipped_sitemaps_index_file}.gz"
  end

  def unzipped_sitemaps_index_file
    "#{sitemaps_dir}/sitemap_index.xml"
  end

  def unzipped_first_sitemap_file
    "#{sitemaps_dir}/sitemap.xml"
  end

  def first_sitemap_file
    "#{sitemaps_dir}/sitemap.xml.gz"
  end

  def second_sitemap_file
    "#{sitemaps_dir}/sitemap_1.xml.gz"
  end

  def third_sitemap_file
    "#{sitemaps_dir}/sitemap_2.xml.gz"
  end

  def sitemaps_dir
    tmp_dir
  end

  def tmp_dir
    '/tmp'
  end

  def ns
    {'s' => 'http://www.sitemaps.org/schemas/sitemap/0.9'}
  end

  def elements(filename, el)
    file_class = filename.include?('.gz') ? Zlib::GzipReader : File
    data = Nokogiri::XML.parse(file_class.open(filename).read)
    data.search("//s:#{el}", ns)
  end

  def num_elements(filename, el)
    elements(filename, el).size
  end
end
