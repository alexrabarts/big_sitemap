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

  should 'generate a sitemap index file' do
    generate_sitemap_files
    assert File.exists?(sitemaps_index_file)
  end

  should 'generate a single sitemap model file' do
    create_sitemap
    add_model
    @sitemap.generate
    assert File.exists?(single_sitemaps_model_file), "#{single_sitemaps_model_file} exists"
  end

  should 'generate exactly two sitemap model files' do
    generate_exactly_two_model_sitemap_files
    assert File.exists?(first_sitemaps_model_file), "#{first_sitemaps_model_file} exists"
    assert File.exists?(second_sitemaps_model_file), "#{second_sitemaps_model_file} exists"
    third_sitemaps_model_file = "#{sitemaps_dir}/sitemap_test_model_3.xml.gz"
    assert !File.exists?(third_sitemaps_model_file), "#{third_sitemaps_model_file} does not exist"
  end

  should 'clean all sitemap files' do
    generate_sitemap_files
    assert Dir.entries(sitemaps_dir).size > 2, "#{sitemaps_dir} is not empty" # ['.', '..'].size == 2
    @sitemap.clean
    assert_equal 2, Dir.entries(sitemaps_dir).size, "#{sitemaps_dir} is empty"
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
      generate_sitemap_files
      assert_equal 1, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain one lastmod element' do
      generate_sitemap_files
      assert_equal 1, num_elements(sitemaps_index_file, 'lastmod')
    end

    should 'contain two loc elements' do
      generate_exactly_two_model_sitemap_files
      assert_equal 2, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain two lastmod elements' do
      generate_exactly_two_model_sitemap_files
      assert_equal 2, num_elements(sitemaps_index_file, 'lastmod')
    end
  end

  context 'Sitemap model file' do
    should 'contain one urlset element' do
      generate_sitemap_files
      assert_equal 1, num_elements(single_sitemaps_model_file, 'urlset')
    end

    should 'contain several loc elements' do
      generate_sitemap_files
      assert_equal default_num_items, num_elements(single_sitemaps_model_file, 'loc')
    end

    should 'contain several lastmod elements' do
      generate_sitemap_files
      assert_equal default_num_items, num_elements(single_sitemaps_model_file, 'lastmod')
    end

    should 'contain several changefreq elements' do
      generate_sitemap_files
      assert_equal default_num_items, num_elements(single_sitemaps_model_file, 'changefreq')
    end

    should 'contain one loc element' do
      generate_exactly_two_model_sitemap_files
      assert_equal 1, num_elements(first_sitemaps_model_file, 'loc')
      assert_equal 1, num_elements(second_sitemaps_model_file, 'loc')
    end

    should 'contain one lastmod element' do
      generate_exactly_two_model_sitemap_files
      assert_equal 1, num_elements(first_sitemaps_model_file, 'lastmod')
      assert_equal 1, num_elements(second_sitemaps_model_file, 'lastmod')
    end

    should 'contain one changefreq element' do
      generate_exactly_two_model_sitemap_files
      assert_equal 1, num_elements(first_sitemaps_model_file, 'changefreq')
      assert_equal 1, num_elements(second_sitemaps_model_file, 'changefreq')
    end

    should 'strip leading slashes from controller paths' do
      create_sitemap
      @sitemap.add(:model => TestModel, :path => '/test_controller').generate
      assert(
        !elements(single_sitemaps_model_file, 'loc').first.text.match(/\/\/test_controller\//),
        'URL does not contain a double-slash before the controller path'
      )
    end
  end

  context 'add method' do
    should 'be chainable' do
      create_sitemap
      assert_equal BigSitemap, @sitemap.add(:model => TestModel, :path => 'test_controller').class
    end
  end

  context 'clean method' do
    should 'be chainable' do
      create_sitemap
      assert_equal BigSitemap, @sitemap.clean.class
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

    def generate_sitemap_files
      create_sitemap
      add_model
      @sitemap.generate
    end

    def generate_exactly_two_model_sitemap_files
      create_sitemap(:max_per_sitemap => 1, :batch_size => 1)
      add_model(:num_items => 2)
      @sitemap.generate
    end

    def add_model(options={})
      num_items = options.delete(:num_items) || default_num_items
      TestModel.stubs(:num_items).returns(num_items)
      @sitemap.add({:model => TestModel, :path => 'test_controller'}.update(options))
    end

    def default_num_items
      10
    end

    def sitemaps_index_file
      "#{sitemaps_dir}/sitemap_index.xml.gz"
    end

    def single_sitemaps_model_file
      "#{sitemaps_dir}/sitemap_test_model.xml.gz"
    end

    def first_sitemaps_model_file
      "#{sitemaps_dir}/sitemap_test_model_1.xml.gz"
    end

    def second_sitemaps_model_file
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