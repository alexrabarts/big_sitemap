require 'uri'
require 'fileutils'

require 'big_sitemap/builder'

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => Builder::MAX_URLS,
    :batch_size      => 1001,
    :document_path   => 'sitemaps/',
    :gzip            => true,

    # opinionated
    :ping_google => true,
    :ping_yahoo  => false, # needs :yahoo_app_id
    :ping_bing   => false,
    :ping_ask    => false
  }

  COUNT_METHODS     = [:count_for_sitemap, :count]
  FIND_METHODS      = [:find_for_sitemap, :all]
  TIMESTAMP_METHODS = [:updated_at, :updated_on, :updated, :created_at, :created_on, :created]
  PARAM_METHODS     = [:to_param, :id]

  def initialize(options={})
    @options = DEFAULTS.merge options
    @options[:document_path] ||= @options[:path] #for legacy reasons

    if @options[:max_per_sitemap] <= 1
      raise ArgumentError, '":max_per_sitemap" must be greater than 1'
    end

    if @options[:url_options]
      @options[:base_url] = URI::Generic.build( {:scheme => "http"}.merge(@options.delete(:url_options)) ).to_s
    end

    unless @options[:base_url]
      raise ArgumentError, 'you must specify either ":url_options" hash or ":base_url" string'
    end
    @options[:url_path] ||= @options[:document_path]

    if @options[:batch_size] > @options[:max_per_sitemap]
      raise ArgumentError, '":batch_size" must be less than ":max_per_sitemap"'
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

  def add(model, options={})
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

  def add_static(url, time = nil, frequency = nil, priority = nil)
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

  def table_name(model)
    model.table_name
  end

  def file_name(name)
    name = table_name(name) unless name.is_a? String
    File.join(@options[:document_full], "sitemap_#{name}")
  end

  def dir_files
    File.join(@options[:document_full], "sitemap_*.{xml,xml.gz}")
  end

  def clean
    Dir[dir_files].each do |file|
      FileUtils.rm file
    end
    self
  end

  def generate
    prepare_update

    generate_models
    generate_static
    generate_sitemap_index
    self
  end

  def generate_models
    for model, options in @sources
      with_sitemap(model, options.dup) do |sitemap|
        last_id = nil #id of last processed item
        count_method = pick_method(model, COUNT_METHODS)
        find_method  = pick_method(model, FIND_METHODS)
        raise ArgumentError, "#{model} must provide a count_for_sitemap class method" if count_method.nil?
        raise ArgumentError, "#{model} must provide a find_for_sitemap class method" if find_method.nil?

        find_options = {}
        [:conditions, :limit, :joins, :select, :order, :include, :group].each do |key|
          find_options[key] = options.delete(key)
        end

        primary_column   = options.delete(:primary_column)

        count = model.send(count_method, find_options.merge(:select => (primary_column || '*'), :include => nil))
        count = find_options[:limit].to_i if find_options[:limit] && find_options[:limit].to_i < count
        num_sitemaps = 1
        num_batches  = 1

        if count > @options[:batch_size]
          num_batches  = (count.to_f / @options[:batch_size].to_f).ceil
          num_sitemaps = (count.to_f / @options[:max_per_sitemap].to_f).ceil
        end
        batches_per_sitemap = num_batches.to_f / num_sitemaps.to_f

        for sitemap_num in 1..num_sitemaps
          # Work out the start and end batch numbers for this sitemap
          batch_num_start = sitemap_num == 1 ? 1 : ((sitemap_num * batches_per_sitemap).ceil - batches_per_sitemap + 1).to_i
          batch_num_end   = (batch_num_start + [batches_per_sitemap, num_batches].min).floor - 1

          for batch_num in batch_num_start..batch_num_end
            offset        = (batch_num - 1) * @options[:batch_size]
            limit         = (count - offset) < @options[:batch_size] ? (count - offset) : @options[:batch_size]
            find_options.update(:limit => limit, :offset => offset) if num_batches > 1

            if last_id && primary_column
              find_options.update(:limit => limit, :offset => nil)
              primary_column_value = escape_if_string last_id #escape '
              find_options.update(:conditions => [find_options[:conditions], "(#{primary_column} > #{primary_column_value})"].compact.join(' AND '))
            end

            model.send(find_method, find_options).each do |record|
              last_mod = options[:last_modified]
              if last_mod.is_a?(Proc)
                last_mod = last_mod.call(record)
              elsif last_mod.nil?
                last_mod_method = pick_method(record, TIMESTAMP_METHODS)
                last_mod = last_mod_method.nil? ? Time.now : record.send(last_mod_method)
              end

              param_method = pick_method(record, PARAM_METHODS)

              location =
                if options[:location].is_a?(Proc)
                  options[:location].call(record)
                else
                  File.join @options[:base_url], options[:path], record.send(param_method).to_s
                end

              change_frequency = options[:change_frequency] || 'weekly'
              freq = change_frequency.is_a?(Proc) ? change_frequency.call(record) : change_frequency

              priority = options[:priority]
              pri = priority.is_a?(Proc) ? priority.call(record) : priority

              last_id = primary_column ? record.send(primary_column) : nil
              sitemap.add_url!(location, last_mod, freq, pri, last_id)
            end
          end
        end
      end
    end
    self
  end

  def generate_static
    return self if Array(@static_pages).empty?
    with_sitemap('static', :type => 'static') do |sitemap|
      @static_pages.each do |location, last_mod, freq, pri|
        sitemap.add_url!(location, last_mod, freq, pri)
      end
    end
    self
  end

  # Create a sitemap index document
  def generate_sitemap_index(files = nil)
    files ||= Dir[dir_files]
    with_sitemap 'index', :type => 'index' do |sitemap|
      for path in files
        next if path =~ /index/
        sitemap.add_url!(url_for_sitemap(path), File.stat(path).mtime)
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
  end

  private

  def prepare_update
    @files_to_move = []
    @sources.each do |model, options|
      if options[:partial_update] && (primary_column = options[:primary_column]) && (last_id = get_last_id(options[:filename]))
        primary_column_value       = escape_if_string last_id #escape '
        options[:conditions]       = [options[:conditions], "(#{primary_column} >= #{primary_column_value})"].compact.join(' AND ')
        options[:start_part_id]    = last_id
      end
    end
  end

  def lock!(lock_file = 'generator.lock')
    lock_file = File.join(@options[:document_full], lock_file)
    File.open(lock_file, 'w', File::EXCL)
  end

  def unlock!(lock_file = 'generator.lock')
    lock_file = File.join(@options[:document_full], lock_file)
    FileUtils.rm lock_file
  end

  def with_sitemap(name, options={})
    options[:filename] ||= file_name(name)
    options[:type]     ||= 'sitemap'
    options[:max_urls] ||= @options["max_per_#{options[:type]}".to_sym]
    options[:gzip]     ||= @options[:gzip]
    options[:indent]     = options[:gzip] ? 0 : 2

    sitemap = if options[:type] == 'index'
      IndexBuilder.new(options)
    elsif options[:geo]
      options[:filename] << '_kml'
      GeoBuilder.new(options)
    else
      Builder.new(options)
    end

    begin
      yield sitemap
    ensure
      sitemap.close!
      @sitemap_files.concat sitemap.paths!
    end
  end

  def get_last_id(filename)
    Dir["#{filename}*.{xml,xml.gz}"].map do |file|
      file.to_s.scan(/#{filename}_(.+).xml/).flatten.last.to_i
    end.sort.last
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

  def escape_if_string(value)
    (value.to_i.to_s == value.to_s) ?  value.to_i : "'#{value.gsub("'", %q(\\\'))}'"
  end

  def url_for_sitemap(path)
    File.join @options[:base_url], @options[:url_path], File.basename(path)
  end

end


class BigSitemapRails < BigSitemap

  if defined?(Rails) && Rails.version < "3"
    include ActionController::UrlWriter
  end

  def initialize(options={})
    raise "No Rails Environment loaded" unless defined? Rails
    require 'action_controller'

    if Rails.version >= "3"
      self.class.send(:include, Rails.application.routes.url_helpers)
    end

    DEFAULTS.merge!(:document_root => "#{Rails.root}/public", :url_options => default_url_options)
    super(options)
  end

end


class BigSitemapMerb < BigSitemap

  def initialize(options={})
    raise "No Merb Environment loaded" unless defined? Merb
    require 'extlib'

    DEFAULTS.merge!(:document_root => "#{Merb.root}/public")
    super(options)
  end

  def table_name(model)
    Extlib::Inflection.tableize(model.to_s)
  end

end
