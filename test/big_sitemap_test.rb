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

  should 'generate sitemap index file' do
    generate_sitemap { add '/foo' }
    assert File.exists? first_sitemap_file
  end

  should 'generate static file' do
    generate_sitemap { add '/foo' }
    assert File.exists? first_sitemap_file
  end

  should 'should add paths' do
    generate_sitemap do
      add '/', {:last_modified => Time.now, :change_frequency => 'weekly', :priority => 0.5}
      add '/navigation/about/us', {:last_modified => Time.now, :change_frequency => 'weekly', :priority => 0.5}
    end

    elems = elements first_sitemap_file, 'loc'
    assert_equal 'http://example.com/', elems.first.text
    assert_equal 'http://example.com/navigation/about/us', elems.last.text
  end

  should 'add to dynamic collection to sitemap' do
    generate_sitemap do
      add_collection TestModel.find_for_sitemap(:limit => 3), 'url_for_sitemap', {:last_modified => Time.now, :change_frequency => 'weekly', :priority => 0.5}
    end

    elems = elements first_sitemap_file, 'loc'
    assert_equal 3, elems.size
  end

  should 'add to static collection to sitemap' do
    generate_sitemap do
      static_pages_for_sitemap = %w(/terms_and_conditions /privacy_policy /contact_us)
      add_static_collection static_pages_for_sitemap, {:last_modified => Time.now, :change_frequency => 'weekly', :priority => 0.5}
    end

    elems = elements first_sitemap_file, 'loc'
    assert_equal 3, elems.size
    assert_equal 'http://example.com/terms_and_conditions', elems.first.text
    assert_equal 'http://example.com/contact_us', elems.last.text
  end

  context 'Sitemap index file' do
    should 'contain one sitemapindex element' do
      generate_sitemap { add '/' }
      assert_equal 1, num_elements(sitemaps_index_file, 'sitemapindex')
    end

    should 'contain one sitemap element' do
      generate_sitemap { add '/' }  
      assert_equal 1, num_elements(sitemaps_index_file, 'sitemap')
    end

    should 'contain one loc element' do
      generate_sitemap { add '/' }  
      assert_equal 1, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain one lastmod element' do
      generate_sitemap { add '/' }  
      assert_equal 1, num_elements(sitemaps_index_file, 'lastmod')
    end

    should 'contain two loc elements' do
      generate_sitemap(:max_per_sitemap => 2) do
        4.times { |i| add "/#{i}" }
      end

      assert_equal 2, num_elements(sitemaps_index_file, 'loc')
    end

    should 'contain two lastmod elements' do
      generate_sitemap(:max_per_sitemap => 2) do
        4.times { |i| add "/#{i}" }
      end

      assert_equal 2, num_elements(sitemaps_index_file, 'lastmod')
    end

    should 'not be gzipped' do
      generate_sitemap(:gzip => false) { add '/' }
      assert File.exists?(unzipped_sitemaps_index_file)
    end
  end

  context 'Sitemap file' do
    should 'contain one urlset element' do
      generate_sitemap { add '/' }
      assert_equal 1, num_elements(first_sitemap_file, 'urlset')
    end

    should 'contain several loc elements' do
      generate_sitemap do
        3.times { |i| add "/#{i}" }
      end

      assert_equal 3, num_elements(first_sitemap_file, 'loc')
    end

    should 'contain several lastmod elements' do
      generate_sitemap do
        3.times { |i| add "/#{i}", :last_modified => Time.now }
      end

      assert_equal 3, num_elements(first_sitemap_file, 'lastmod')
    end

    should 'contain several changefreq elements' do
      generate_sitemap do
        3.times { |i| add "/#{i}" }
      end

      assert_equal 3, num_elements(first_sitemap_file, 'changefreq')
    end

    should 'contain several priority elements' do
      generate_sitemap do
        3.times { |i| add "/#{i}", :priority => 0.2 }
      end

      assert_equal 3, num_elements(first_sitemap_file, 'priority')
    end

    should 'have a change frequency of weekly by default' do
      generate_sitemap do
        3.times { add '/' }
      end

      assert_equal 'weekly', elements(first_sitemap_file, 'changefreq').first.text
    end

    should 'have a change frequency of daily' do
      generate_sitemap { add '/', :change_frequency => 'daily' }
      assert_equal 'daily', elements(first_sitemap_file, 'changefreq').first.text
    end

    should 'have a priority of 0.2' do
      generate_sitemap { add '/', :priority => 0.2 }
      assert_equal '0.2', elements(first_sitemap_file, 'priority').first.text
    end

    should 'contain two loc element' do
      generate_sitemap(:max_per_sitemap => 2) do
        4.times { |i| add "/#{i}" }
      end

      assert_equal 2, num_elements(first_sitemap_file, 'loc')
      assert_equal 2, num_elements(second_sitemap_file, 'loc')
    end

    should 'contain two changefreq elements' do
      generate_sitemap(:max_per_sitemap => 2) do
        4.times { |i| add "/#{i}" }
      end

      assert_equal 2, num_elements(first_sitemap_file, 'changefreq')
      assert_equal 2, num_elements(second_sitemap_file, 'changefreq')
    end

    should 'contain two priority element' do
      generate_sitemap(:max_per_sitemap => 2) do
        4.times { |i| add "/#{i}", :priority => 0.2 }
      end

      assert_equal 2, num_elements(first_sitemap_file, 'priority')
      assert_equal 2, num_elements(second_sitemap_file, 'priority')
    end

    should 'not be gzipped' do
      generate_sitemap(:gzip => false) { add '/' }
      assert File.exists?(unzipped_first_sitemap_file)
    end

    should 'contain unique elements' do
      generate_sitemap do
        2.times { add '/' }
      end

      assert_equal 1, num_elements(first_sitemap_file, 'url')
    end
  end

  context 'sanatize XML chars' do
    should 'should transform ampersands' do
      generate_sitemap { add '/something&else' }
      elems = elements(first_sitemap_file, 'loc')

      assert Zlib::GzipReader.open(first_sitemap_file).read.include?("/something&amp;else")
      assert_equal 'http://example.com/something&else', elems.first.text
    end
  end

  context 'clean method' do
    should 'be chainable' do
      sitemap = generate_sitemap { add '/' }
      assert_equal BigSitemap, sitemap.clean.class
    end

    should 'clean all sitemap files' do
      sitemap = generate_sitemap { add '/' }
      assert Dir["#{sitemaps_dir}/sitemap*"].size > 0, "#{sitemaps_dir} has sitemap files"
      sitemap.clean
      assert_equal 0, Dir["#{sitemaps_dir}/sitemap*"].size, "#{sitemaps_dir} is empty of sitemap files"
    end
  end

  context 'sitemap index' do
    should 'generate for all xml files in directory' do
      sitemap = generate_sitemap {}
      File.open("#{sitemaps_dir}/sitemap_file1.xml", 'w')
      File.open("#{sitemaps_dir}/sitemap_file2.xml.gz", 'w')
      File.open("#{sitemaps_dir}/sitemap_file3.txt", 'w')
      File.open("#{sitemaps_dir}/file4.xml", 'w')
      File.open(unzipped_sitemaps_index_file, 'w')
      sitemap.send :generate_sitemap_index

      elem = elements(sitemaps_index_file, 'loc')
      assert_equal 2, elem.size #no index and file3 and file4 found
      assert_equal "http://example.com/sitemap_file1.xml", elem.first.text
      assert_equal "http://example.com/sitemap_file2.xml.gz", elem.last.text
    end

    should 'generate for all for given file' do
      sitemap = generate_sitemap {}
      File.open("#{sitemaps_dir}/sitemap_file1.xml", 'w')
      File.open("#{sitemaps_dir}/sitemap_file2.xml.gz", 'w')
      files = ["#{sitemaps_dir}/sitemap_file1.xml", "#{sitemaps_dir}/sitemap_file2.xml.gz"]
      sitemap.send :generate_sitemap_index, files

      elem = elements(sitemaps_index_file, 'loc')
      assert_equal 2, elem.size
      assert_equal "http://example.com/sitemap_file1.xml", elem.first.text
      assert_equal "http://example.com/sitemap_file2.xml.gz", elem.last.text
    end
  end

  context 'partial update' do
    should 'not recreate old files' do
      # The first run should generate all the files
      generate_sitemap(:max_per_sitemap => 2, :partial_update => true, :gzip => false) do
        [10, 20, 30, 40, 50].each do |i|
          add "/#{i}", :id => i
        end
      end

      filename = "#{sitemaps_dir}/sitemap"

      assert File.exists? "#{filename}.xml" # ids 10 and 20
      assert File.exists? "#{filename}_30.xml" # ids 30 and 40
      assert File.exists? "#{filename}_50.xml" # id 50

      # Move the files so we can test if they are re-created
      FileUtils.mv "#{filename}.xml", "#{filename}.bak.xml"
      FileUtils.mv "#{filename}_30.xml", "#{filename}_30.bak.xml"

      # Store the original file size so we can compare it later
      original_size = File.size "#{filename}_50.xml"

      start_id = nil

      # Run a new update starting from the first ID of the last sitemap
      generate_sitemap(:max_per_sitemap => 2, :partial_update => true, :gzip => false) do
        start_id = first_id_of_last_sitemap

        [50, 60, 70, 80].each do |i|
          add "/#{i}", :id => i
        end
      end

      # Check the correct ID is returned for the beginning of the last sitemap
      assert_equal 50, start_id

      # Since we did a partial update, the earlier files shouldn't have been recreated
      assert !File.exists?("#{filename}.xml") # ids 10 and 20
      assert !File.exists?("#{filename}_30.xml") # ids 30 and 40

      # The last file of the first run should have been recreated with new records
      # and a larger file size
      assert (original_size < File.size?("#{filename}_50.xml"))

      elems = elements("#{filename}_50.xml", 'loc').map(&:text)

      assert_equal 2, elems.size

      [50, 60].each do |i|
        assert elems.include? "http://example.com/#{i}"
      end

      elems = elements(unzipped_sitemaps_index_file, 'loc').map(&:text)

      assert elems.include? 'http://example.com/sitemap.bak.xml'
      assert elems.include? 'http://example.com/sitemap_30.bak.xml'
      assert elems.include? 'http://example.com/sitemap_50.xml'
      assert elems.include? 'http://example.com/sitemap_70.xml'
    end

    context 'lockfile' do
      should 'create and delete lock file' do
        sitemap = BigSitemap.new(:base_url => 'http://example.com', :document_root => tmp_dir)

        sitemap.with_lock do
          assert File.exists?("#{sitemaps_dir}/generator.lock")
        end

        assert !File.exists?("#{sitemaps_dir}/generator.lock")
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

end
