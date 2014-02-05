require 'uri'
require 'fileutils'

require 'big_sitemap/builder'

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => Builder::MAX_URLS,
    :document_path   => '/',
    :gzip            => true,

    # Opinionated
    :ping_google => true,
    :ping_yahoo  => false, # needs :yahoo_app_id
    :ping_bing   => false,
    :ping_ask    => false, 
    :ping_yandex => false
  }

  class << self
    def generate(options={}, &block)
      @sitemap = self.new(options)

      @sitemap.first_id_of_last_sitemap = first_id_of_last_sitemap

      instance_eval(&block)

      @sitemap.with_lock do
        @sitemap.generate(options)
      end
    end

    private

    def first_id_of_last_sitemap
      Dir["#{@sitemap.document_full}sitemap*.{xml,xml.gz}"].map do |file|
        file.to_s.scan(/sitemap_(.+).xml/).flatten.last.to_i
      end.sort.last
    end

    def add(path, options={})
      @sitemap.add_path(path, options)
    end

    def add_collection(collection, url_method='url_for_sitemap', options={})
      collection.each do |member|
          add member.send(url_method), options
      end
    end

    def add_static_collection(collection, options={})
      collection.each do |member|
        add member, options
      end
    end
  end

  def initialize(options={})
    @options = DEFAULTS.merge options

    if @options[:max_per_sitemap] <= 1
      raise ArgumentError, '":max_per_sitemap" must be greater than 1'
    end

    if @options[:url_options] && !@options[:base_url]
      @options[:base_url] = URI::Generic.build( {:scheme => "http"}.merge(@options.delete(:url_options)) ).to_s
    end

    unless @options[:base_url]
      raise ArgumentError, 'you must specify either ":url_options" hash or ":base_url" string'
    end
    @options[:url_path] ||= @options[:document_path]

    unless @options[:document_root]
      raise ArgumentError, 'Document root must be specified with the ":document_root" option"'
    end

    @options[:document_full] ||= File.join(@options[:document_root], @options[:document_path])
    unless @options[:document_full]
      raise ArgumentError, 'Document root must be specified with the ":document_root" option, the full path with ":document_full"'
    end

    Dir.mkdir(@options[:document_full]) unless File.exists?(@options[:document_full])

    @sources       = []
    @models        = []
    @sitemap_files = []
  end

  def first_id_of_last_sitemap
    @first_id_of_last_sitemap
  end

  def first_id_of_last_sitemap=(first_id)
    @first_id_of_last_sitemap = first_id
  end

  def document_full
    @options[:document_full]
  end

  def add(model, options={})
    warn 'BigSitemap#add is deprecated.  Please use BigSitemap.generate and call add inside the block (in BigSitemap 1.0.0+).  You will have to perform the find and generate the path for each record yourself.'
    @models << model

    filename_suffix = @models.count(model) - 1

    options[:path]           ||= table_name(model)
    options[:filename]       ||= file_name(model)
    options[:primary_column] ||= 'id' if model.new.respond_to?('id')
    options[:partial_update]   = @options[:partial_update] && options[:partial_update] != false

    options[:filename] << "_#{filename_suffix}" unless filename_suffix == 0

    @sources << [model, options.dup]

    self
  end

  def add_path(path, options)
    @paths ||= []
    @paths << [path, options]
    self
  end

  def add_static(url, time = nil, frequency = nil, priority = nil)
    warn 'BigSitemap#add_static is deprecated.  Please use BigSitemap#add_path instead'
    @static_pages ||= []
    @static_pages << [url, time, frequency, priority]
    self
  end

  def with_lock
    lock!
    begin
      yield
    ensure
      unlock!
    end
  rescue Errno::EACCES => e
    STDERR.puts 'Lockfile exists' if $VERBOSE
  end

  def file_name(name=nil)
    name   = table_name(name) unless (name.nil? || name.is_a?(String))
    prefix = 'sitemap'
    prefix << '_' unless name.nil?
    File.join(@options[:document_full], "#{prefix}#{name}")
  end

  def dir_files
    File.join(@options[:document_full], "sitemap*.{xml,xml.gz}")
  end

  def clean
    Dir[dir_files].each do |file|
      FileUtils.rm file
    end

    self
  end

  # TODO: Deprecate (move to private)
  def generate(options={})
    clean unless options[:partial_update]

    add_urls

    generate_sitemap_index

    ping_search_engines

    self
  end

  def add_urls
    return self if Array(@paths).empty?

    with_sitemap do |builder|
      @paths.uniq!
      @paths.each do |path, options|
        url = URI.join(@options[:base_url], path)
        builder.add_url! url, options
      end
    end

    self
  end

  # Create a sitemap index document
  def generate_sitemap_index(files=nil)
    files ||= Dir[dir_files]

    with_sitemap({:name => 'index', :type => 'index'}) do |sitemap|
      for path in files
        next if path =~ /index/
        sitemap.add_url! url_for_sitemap(path), :last_modified => File.stat(path).mtime
      end
    end

    self
  end

  def ping_search_engines
    require 'net/http'
    require 'cgi'

    sitemap_uri = CGI::escape(url_for_sitemap(@sitemap_files.last))

    if @options[:ping_google]
      Net::HTTP.get('www.google.com', "/webmasters/tools/ping?sitemap=#{sitemap_uri}")
    end

    if @options[:ping_yahoo]
      if @options[:yahoo_app_id]
        Net::HTTP.get(
          'search.yahooapis.com', "/SiteExplorerService/V1/updateNotification?" +
            "appid=#{@options[:yahoo_app_id]}&url=#{sitemap_uri}"
        )
      else
        STDERR.puts 'unable to ping Yahoo: no ":yahoo_app_id" provided'
      end
    end

    if @options[:ping_bing]
      Net::HTTP.get('www.bing.com', "/webmaster/ping.aspx?siteMap=#{sitemap_uri}")
    end

    if @options[:ping_ask]
      Net::HTTP.get('submissions.ask.com', "/ping?sitemap=#{sitemap_uri}")
    end

    if @options[:ping_yandex]
      Net::HTTP.get('webmaster.yandex.ru', "/wmconsole/sitemap_list.xml?host=#{sitemap_uri}")
    end
  end

  private

  def lock!(lock_file = 'generator.lock')
    lock_file = File.join(@options[:document_full], lock_file)
    File.open(lock_file, 'w', File::EXCL)
  end

  def unlock!(lock_file = 'generator.lock')
    lock_file = File.join(@options[:document_full], lock_file)
    FileUtils.rm lock_file
  end

  def with_sitemap(options={})
    options[:filename]       ||= file_name(options[:name])
    options[:type]           ||= 'sitemap'
    options[:max_urls]       ||= @options["max_per_#{options[:type]}".to_sym]
    options[:gzip]           ||= @options[:gzip]
    options[:indent]         ||= 2
    options[:partial_update] ||= @options[:partial_update]
    options[:start_part_id]  ||= first_id_of_last_sitemap

    sitemap = if options[:type] == 'index'
      IndexBuilder.new(options)
    else
      Builder.new(options)
    end

    begin
      yield sitemap
    ensure
      sitemap.close!
      @sitemap_files.concat sitemap.filepaths!
    end
  end

  def pick_method(model, candidates)
    method = nil
    candidates.each do |candidate|
      if model.respond_to? candidate
        method = candidate
        break
      end
    end
    method
  end

  def url_for_sitemap(path)
    File.join @options[:base_url], @options[:url_path], File.basename(path)
  end

end


class BigSitemapRails < BigSitemap
  def self.generate(options={}, &block)
    raise 'No Rails Environment loaded' unless defined? Rails

    DEFAULTS.merge!(:document_root => "#{Rails.root}/public", :url_options => default_url_options)
    super(options, &block)
  end
end


class BigSitemapMerb < BigSitemap
  def self.generate(options={}, &block)
    raise 'No Merb Environment loaded' unless defined? ::Merb
    require 'extlib'

    DEFAULTS.merge!(:document_root => "#{Merb.root}/public")
    super(options, &block)
  end
end
