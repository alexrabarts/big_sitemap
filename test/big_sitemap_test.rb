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

  should 'generate the same base URL with :base_url option' do
    options = {:document_root => tmp_dir}
    url = 'http://example.com'
    sitemap = BigSitemap.new(options.merge(:base_url => url))

    assert_equal url, sitemap.instance_variable_get(:@options)[:base_url]
  end

  should 'generate the same base URL with :url_options option' do
    options = {:document_root => tmp_dir}
    url = 'http://example.com'
    sitemap = BigSitemap.new(options.merge(:url_options => {:host => 'example.com'}))

    assert_equal url, sitemap.instance_variable_get(:@options)[:base_url]
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

  should 'generate two sitemap model files for the same model with different options' do
    create_sitemap
    add_model(:path => 'foo')
    add_model(:path => 'bar')
    @sitemap.generate

    assert File.exists?(first_sitemaps_model_file), "#{first_sitemaps_model_file} exists"
    assert File.exists?(second_sitemaps_model_file), "#{second_sitemaps_model_file} exists"
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

    should 'be able to use a lambda to specify lastmod' do
      generate_one_sitemap_model_file(:last_modified => lambda {|m| m.updated_at})
      assert_equal TestModel.new.updated_at.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00'), elements(first_sitemaps_model_file, 'lastmod').first.text
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
      add_model
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

  context 'add static method' do
    should 'should generate static content' do
      create_sitemap
      @sitemap.add_static('/', Time.now, 'weekly', 0.5)
      @sitemap.add_static('/about', Time.now, 'weekly', 0.5)
      @sitemap.generate_static
      elems = elements(static_sitemaps_file, 'loc')
      assert_equal "/", elems.first.text
      assert_equal "/about", elems.last.text
    end
  end

  context 'sanatize XML chars' do
    should 'should transform ampersands' do
      create_sitemap
      @sitemap.add_static('/something&else', Time.now, 'weekly', 0.5)
      @sitemap.generate_static
      elems = elements(static_sitemaps_file, 'loc')
      assert Zlib::GzipReader.open(static_sitemaps_file).read.include?("/something&amp;else")
      assert_equal "/something&else", elems.first.text
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

  context 'sitemap index' do
    should 'generate for all xml files in directory' do
      create_sitemap
      @sitemap.clean
      File.open("#{sitemaps_dir}/sitemap_file1.xml", 'w')
      File.open("#{sitemaps_dir}/sitemap_file2.xml.gz", 'w')
      File.open("#{sitemaps_dir}/sitemap_file3.txt", 'w')
      File.open("#{sitemaps_dir}/file4.xml", 'w')
      File.open(unzipped_sitemaps_index_file, 'w')
      @sitemap.send :generate_sitemap_index

      elem = elements(sitemaps_index_file, 'loc')
      assert_equal 2, elem.size #no index and file3 and file4 found
      assert_equal "http://example.com/sitemaps/sitemap_file1.xml", elem.first.text
      assert_equal "http://example.com/sitemaps/sitemap_file2.xml.gz", elem.last.text
    end

    should 'generate for all for given file' do
      create_sitemap
      @sitemap.clean
      File.open("#{sitemaps_dir}/sitemap_file1.xml", 'w')
      File.open("#{sitemaps_dir}/sitemap_file2.xml.gz", 'w')
      files = ["#{sitemaps_dir}/sitemap_file1.xml", "#{sitemaps_dir}/sitemap_file2.xml.gz"]
      @sitemap.send :generate_sitemap_index, files

      elem = elements(sitemaps_index_file, 'loc')
      assert_equal 2, elem.size
      assert_equal "http://example.com/sitemaps/sitemap_file1.xml", elem.first.text
      assert_equal "http://example.com/sitemaps/sitemap_file2.xml.gz", elem.last.text
    end
  end

  context 'get_last_id' do
    should 'return last id' do
      create_sitemap.clean
      filename = "#{sitemaps_dir}/sitemap_file"
      File.open("#{filename}_1.xml", 'w')
      File.open("#{filename}_23.xml", 'w')
      File.open("#{filename}_42.xml.gz", 'w')
      File.open("#{filename}_9.xml", 'w')
      assert_equal 42, @sitemap.send(:get_last_id, filename)
    end

    should 'return nil' do
      create_sitemap.clean
      filename = "#{sitemaps_dir}/sitemap_file"
      assert_equal nil, @sitemap.send(:get_last_id, filename)
    end
  end

  context 'partial update' do

    context 'prepare_update' do
      should 'generate correct condition for partial update' do
        filename = "#{sitemaps_dir}/sitemap_test_models"

        create_sitemap(:partial_update => true).clean
        add_model(:num_items => 50) #TestModel

        File.open("#{filename}_23.xml", 'w')
        assert_equal "(id >= 23)", @sitemap.send(:prepare_update).first.last[:conditions]

        File.open("#{filename}_42.xml", 'w')
        assert_equal "(id >= 23) AND (id >= 42)", @sitemap.send(:prepare_update).first.last[:conditions]
      end

      should 'generate correct condition for partial update with custom column' do
        filename = "#{sitemaps_dir}/sitemap_test_models"

        create_sitemap(:partial_update => true).clean
        add_model(:num_items => 50, :primary_column => 'name') #TestModel

        File.open("#{filename}_666.xml", 'w')
        assert_equal "(name >= 666)", @sitemap.send(:prepare_update).first.last[:conditions]
      end
    end

    should 'generate for all xml files in directory and delete last file' do
      TestModel.current_id = last_id = 27
      filename = "#{sitemaps_dir}/sitemap_test_models"

      create_sitemap(:partial_update => true, :gzip => false, :batch_size => 5, :max_per_sitemap => 5, :max_per_index => 100).clean
      add_model(:num_items => 50 - last_id) #TestModel

      File.open("#{filename}.xml", 'w')
      File.open("#{filename}_5.xml", 'w')
      File.open("#{filename}_9.xml", 'w')
      File.open("#{filename}_23.xml", 'w')
      File.open("#{filename}_#{last_id}.xml", 'w')
      @sitemap.generate

      # Dir["#{sitemaps_dir}/*"].each do |d| puts d; end

      assert File.exists?("#{filename}_48.xml")
      assert File.exists?("#{filename}_#{last_id}.xml")
      elems = elements("#{filename}_#{last_id}.xml", 'loc').map(&:text)

      assert_equal 5, elems.size
      (28..32).each do |i|
        assert elems.include? "http://example.com/test_models/#{i}"
      end

      elems = elements(unzipped_sitemaps_index_file, 'loc').map(&:text)
      assert elems.include? "http://example.com/sitemaps/sitemap_test_models.xml"
      assert elems.include? "http://example.com/sitemaps/sitemap_test_models_9.xml"
      assert elems.include? "http://example.com/sitemaps/sitemap_test_models_#{last_id}.xml"
      assert elems.include? "http://example.com/sitemaps/sitemap_test_models_48.xml"
    end

    should 'generate sitemap, update should respect old files' do
      max_id = 23
      TestModel.current_id = 0
      filename = "#{sitemaps_dir}/sitemap_test_models"

      create_sitemap(:partial_update => true, :gzip => false, :batch_size => 5, :max_per_sitemap => 5, :max_per_index => 100).clean
      add_model(:num_items => max_id) #TestModel
      @sitemap.generate

      # Dir["#{sitemaps_dir}/*"].each do |d| puts d; end

      assert_equal 5, elements("#{filename}.xml", 'loc').size
      assert_equal 5, elements("#{filename}_6.xml", 'loc').size
      assert_equal 3, elements("#{filename}_21.xml", 'loc').size

      TestModel.current_id = 20 #last_id is 21, so start with one below
      create_sitemap(:partial_update => true, :gzip => false, :batch_size => 5, :max_per_sitemap => 5, :max_per_index => 100)
      add_model( :num_items => 48 - TestModel.current_id ) #TestModel
      @sitemap.generate

      assert_equal 5, elements("#{filename}_6.xml", 'loc').size
      assert_equal 5, elements("#{filename}_21.xml", 'loc').size

      # Dir["#{sitemaps_dir}/*"].each do |d| puts d; end

      elems = elements("#{filename}_26.xml", 'loc').map(&:text)
      (26..30).each do |i|
         assert elems.include? "http://example.com/test_models/#{i}"
      end

      #puts `cat /tmp/sitemaps/sitemap_test_models_41.xml`

      assert_equal 3, elements("#{filename}_46.xml", 'loc').size
    end

    context 'escape' do
      should 'add if not number' do
        create_sitemap
        data = {
           42 => 42,
          '23' => 23,
          "test" => "'test'",
          "test10" => "'test10'",
          "10test" => "'10test'",
          "10t' est" => "'10t\\' est'",
        }
        data.each do |key, value|
          assert_equal value, @sitemap.send(:escape_if_string, key)
        end

      end
    end

    context 'lockfile' do
      should 'create and delete lock file' do
        sitemap = BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir)

        sitemap.with_lock do
          assert File.exists?('/tmp/sitemaps/generator.lock')
        end

        assert !File.exists?('/tmp/sitemaps/generator.lock')
      end

      should 'not catch error not related to lock' do
        sitemap = BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir)

        assert_raise RuntimeError do
          sitemap.with_lock do
            raise "Wrong"
          end
        end

      end

      should 'throw error if lock exits' do
        sitemap = BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir)

        sitemap.with_lock do
          sitemap2 = BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir)

          assert_nothing_raised do
            sitemap2.with_lock do
              raise "Should not be called"
            end
          end

        end
      end

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
