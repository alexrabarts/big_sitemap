require File.dirname(__FILE__) + '/test_helper'
require 'nokogiri'

class BigSitemapTest < Test::Unit::TestCase
  def setup
    delete_tmp_files
  end

  def teardown
    delete_tmp_files
  end

  should 'raise an error if the :base_url option is not specified' do
    assert_nothing_raised { BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir) }
    assert_raise(ArgumentError) { BigSitemap.new(:document_root => tmp_dir) }
  end

  should 'generate the same base URL' do
    options = {:document_root => tmp_dir}
    assert_equal(
      BigSitemap.new(options.merge(:base_url => 'http://example.com')).root_url,
      BigSitemap.new(options.merge(:url_options => {:host => 'example.com'})).root_url
    )
  end

  should 'generate a sitemap index file' do
    generate_sitemap_files
    assert File.exists?(sitemaps_index_file)
  end

  should 'generate a single sitemap model file' do
    create_sitemap
    add_model
    @sitemap.generate
    assert File.exists?(first_sitemaps_model_file), "#{first_sitemaps_model_file} exists"
  end

  should 'generate two sitemap model files' do
    generate_two_model_sitemap_files
    assert File.exists?(first_sitemaps_model_file), "#{first_sitemaps_model_file} exists"
    assert File.exists?(second_sitemaps_model_file), "#{second_sitemaps_model_file} exists"
    assert !File.exists?(third_sitemaps_model_file), "#{third_sitemaps_model_file} does not exist"
  end

  context 'Sitemap index file' do
    should 'contain one sitemapindex element' do
      generate_sitemap_files
      assert_equal 1, num_elements(sitemaps_index_file, 'sitemapindex')
    end

    should 'contain one sitemap element' do
      generate_sitemap_files
      assert_equal 1, num_elements(sitemaps_index_file, 'sitemap')
    end

    should 'contain one loc element' do
      generate_one_sitemap_model_file
      assert_equal 1, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain one lastmod element' do
      generate_one_sitemap_model_file
      assert_equal 1, num_elements(sitemaps_index_file, 'lastmod')
    end

    should 'contain two loc elements' do
      generate_two_model_sitemap_files
      assert_equal 2, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain two lastmod elements' do
      generate_two_model_sitemap_files
      assert_equal 2, num_elements(sitemaps_index_file, 'lastmod')
    end

    should 'not be gzipped' do
      generate_sitemap_files(:gzip => false)
      assert File.exists?(unzipped_sitemaps_index_file)
    end
  end

  context 'Sitemap model file' do
    should 'contain one urlset element' do
      generate_one_sitemap_model_file
      assert_equal 1, num_elements(first_sitemaps_model_file, 'urlset')
    end

    should 'contain several loc elements' do
      generate_one_sitemap_model_file
      assert_equal default_num_items, num_elements(first_sitemaps_model_file, 'loc')
    end

    should 'contain several lastmod elements' do
      generate_one_sitemap_model_file
      assert_equal default_num_items, num_elements(first_sitemaps_model_file, 'lastmod')
    end

    should 'contain several changefreq elements' do
      generate_one_sitemap_model_file
      assert_equal default_num_items, num_elements(first_sitemaps_model_file, 'changefreq')
    end

    should 'contain several priority elements' do
      generate_one_sitemap_model_file(:priority => 0.2)
      assert_equal default_num_items, num_elements(first_sitemaps_model_file, 'priority')
    end

    should 'have a change frequency of weekly by default' do
      generate_one_sitemap_model_file
      assert_equal 'weekly', elements(first_sitemaps_model_file, 'changefreq').first.text
    end

    should 'have a change frequency of daily' do
      generate_one_sitemap_model_file(:change_frequency => 'daily')
      assert_equal 'daily', elements(first_sitemaps_model_file, 'changefreq').first.text
    end

    should 'be able to use a lambda to specify change frequency' do
      generate_one_sitemap_model_file(:change_frequency => lambda {|m| m.change_frequency})
      assert_equal TestModel.new.change_frequency, elements(first_sitemaps_model_file, 'changefreq').first.text
    end

    should 'have a priority of 0.2' do
      generate_one_sitemap_model_file(:priority => 0.2)
      assert_equal '0.2', elements(first_sitemaps_model_file, 'priority').first.text
    end

    should 'be able to use a lambda to specify priority' do
      generate_one_sitemap_model_file(:priority => lambda {|m| m.priority})
      assert_equal TestModel.new.priority.to_s, elements(first_sitemaps_model_file, 'priority').first.text
    end

    should 'contain two loc element' do
      generate_two_model_sitemap_files
      assert_equal 2, num_elements(first_sitemaps_model_file, 'loc')
      assert_equal 2, num_elements(second_sitemaps_model_file, 'loc')
    end

    should 'contain two lastmod element' do
      generate_two_model_sitemap_files
      assert_equal 2, num_elements(first_sitemaps_model_file, 'lastmod')
      assert_equal 2, num_elements(second_sitemaps_model_file, 'lastmod')
    end

    should 'contain two changefreq elements' do
      generate_two_model_sitemap_files
      assert_equal 2, num_elements(first_sitemaps_model_file, 'changefreq')
      assert_equal 2, num_elements(second_sitemaps_model_file, 'changefreq')
    end

    should 'contain two priority element' do
      generate_two_model_sitemap_files(:priority => 0.2)
      assert_equal 2, num_elements(first_sitemaps_model_file, 'priority')
      assert_equal 2, num_elements(second_sitemaps_model_file, 'priority')
    end

    should 'strip leading slashes from controller paths' do
      create_sitemap
      @sitemap.add(TestModel, :path => '/test_controller').generate
      assert(
        !elements(first_sitemaps_model_file, 'loc').first.text.match(/\/\/test_controller\//),
        'URL does not contain a double-slash before the controller path'
      )
    end

    should 'not be gzipped' do
      generate_one_sitemap_model_file(:gzip => false)
      assert File.exists?(unzipped_first_sitemaps_model_file)
    end
  end

  context 'add method' do
    should 'be chainable' do
      create_sitemap
      assert_equal BigSitemap, @sitemap.add(TestModel).class
    end
  end

  context 'clean method' do
    should 'be chainable' do
      create_sitemap
      assert_equal BigSitemap, @sitemap.clean.class
    end

    should 'clean all sitemap files' do
      generate_sitemap_files
      assert Dir.entries(sitemaps_dir).size > 2, "#{sitemaps_dir} is not empty" # ['.', '..'].size == 2
      @sitemap.clean
      assert_equal 2, Dir.entries(sitemaps_dir).size, "#{sitemaps_dir} is empty"
    end
  end

  context 'generate method' do
    should 'be chainable' do
      create_sitemap
      assert_equal BigSitemap, @sitemap.generate.class
    end
  end

  private
    def delete_tmp_files
      FileUtils.rm_rf(sitemaps_dir)
    end

    def create_sitemap(options={})
      @sitemap = BigSitemap.new({
        :base_url      => 'http://example.com',
        :document_root => tmp_dir,
        :update_google => false
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
      TestModel.stubs(:num_items).returns(num_items)
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

    def second_sitemaps_model_file
      "#{sitemaps_dir}/sitemap_test_models_1.xml.gz"
    end

    def third_sitemaps_model_file
      "#{sitemaps_dir}/sitemap_test_model_2.xml.gz"
    end

    def sitemaps_dir
      "#{tmp_dir}/sitemaps"
    end

    def tmp_dir
      '/tmp'
    end

    def ns
      {'s' => 'http://www.sitemaps.org/schemas/sitemap/0.9'}
    end

    def elements(filename, el)
      data = Nokogiri::XML.parse(Zlib::GzipReader.open(filename).read)
      data.search("//s:#{el}", ns)
    end

    def num_elements(filename, el)
      elements(filename, el).size
    end
end
