require 'rubygems'
require 'bundler/setup'

require 'test/unit'
require 'shoulda'
require 'mocha'
require 'test/fixtures/test_model'

require 'big_sitemap'

class Test::Unit::TestCase

  def delete_tmp_files
    FileUtils.rm_rf(sitemaps_dir)
  end

  def create_files(*files)
    files.each do |filename|
      File.open(filename, 'w')
    end
  end

  def create_sitemap(options={})
    @sitemap = BigSitemap.new({
      :base_url      => 'http://example.com',
      :document_root => tmp_dir,
      :ping_google => false
    }.update(options))
  end

  def generate_sitemap_files(options={})
    create_sitemap(options)
    add_model
    @sitemap.generate
  end

  def generate_one_sitemap_model_file(options={})
    change_frequency = options.delete(:change_frequency)
    priority         = options.delete(:priority)
    create_sitemap(options.merge(:max_per_sitemap => default_num_items, :batch_size => default_num_items))
    add_model(:change_frequency => change_frequency, :priority => priority)
    @sitemap.generate
  end

  def generate_two_model_sitemap_files(options={})
    change_frequency = options.delete(:change_frequency)
    priority         = options.delete(:priority)
    create_sitemap(options.merge(:max_per_sitemap => 2, :batch_size => 1))
    add_model(:num_items => 4, :change_frequency => change_frequency, :priority => priority)
    @sitemap.generate
  end

  def add_model(options={})
    num_items = options.delete(:num_items) || default_num_items
    TestModel.stubs(:count_for_sitemap).returns(num_items)
    @sitemap.add(TestModel, options)
  end

  def default_num_items
    10
  end

  def sitemaps_index_file
    "#{unzipped_sitemaps_index_file}.gz"
  end

  def unzipped_sitemaps_index_file
    "#{sitemaps_dir}/sitemap_index.xml"
  end

  def unzipped_first_sitemaps_model_file
    "#{sitemaps_dir}/sitemap_test_models.xml"
  end

  def first_sitemaps_model_file
    "#{sitemaps_dir}/sitemap_test_models.xml.gz"
  end

  def static_sitemaps_file
    "#{sitemaps_dir}/sitemap_static.xml.gz"
  end

  def second_sitemaps_model_file
    "#{sitemaps_dir}/sitemap_test_models_1.xml.gz"
  end

  def third_sitemaps_model_file
    "#{sitemaps_dir}/sitemap_test_models_2.xml.gz"
  end

  def sitemaps_dir
    "#{tmp_dir}/sitemaps"
  end

  def tmp_dir
    '/tmp'
  end

  def ns
    {'s' => 'http://www.sitemaps.org/schemas/sitemap/0.9',
     'mobile' => 'http://www.google.com/schemas/sitemap-mobile/1.0'}
  end

  def elements(filename, el, nsp = 's')
    file_class = filename.include?('.gz') ? Zlib::GzipReader : File
    data = Nokogiri::XML.parse(file_class.open(filename).read)
    data.search("//#{nsp}:#{el}", ns)
  end

  def mobile_elements(filename, el)
    elements(filename, el, nsp = 'mobile')
  end

  def num_elements(filename, el)
    elements(filename, el).size
  end
end
