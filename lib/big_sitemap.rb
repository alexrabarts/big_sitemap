require 'uri'
require 'big_sitemap/builder'
require 'extlib'
require 'action_controller' if defined? Rails

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => Builder::MAX_URLS,
    :batch_size      => 1001,
    :path            => 'sitemaps',
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

  include ActionController::UrlWriter if defined? Rails

  def initialize(options)
    @options = DEFAULTS.merge options

    # Use Rails' default_url_options if available
    @default_url_options = defined?(Rails) ? default_url_options : {}

    if @options[:max_per_sitemap] <= 1
      raise ArgumentError, '":max_per_sitemap" must be greater than 1'
    end

    if @options[:url_options]
      @default_url_options.update @options[:url_options]
    elsif @options[:base_url]
      uri = URI.parse(@options[:base_url])
      @default_url_options[:host]     = uri.host
      @default_url_options[:port]     = uri.port
      @default_url_options[:protocol] = uri.scheme
    else
      raise ArgumentError, 'you must specify either ":url_options" hash or ":base_url" string'
    end

    if @options[:batch_size] > @options[:max_per_sitemap]
      raise ArgumentError, '":batch_size" must be less than ":max_per_sitemap"'
    end

    @options[:document_root] ||= begin
      if defined? Rails
        "#{Rails.root}/public"
      elsif defined? Merb
        "#{Merb.root}/public"
      end
    end

    unless @options[:document_root]
      raise ArgumentError, 'Document root must be specified with the ":document_root" option'
    end

    @file_path = "#{@options[:document_root]}/#{strip_leading_slash(@options[:path])}"
    Dir.mkdir(@file_path) unless File.exists? @file_path

    @sources       = []
    @sitemap_files = []
  end

  def add(model, options={})
    options[:path] ||= Extlib::Inflection.tableize(model.to_s)
    @sources << [model, options.dup]
    return self
  end

  def clean
    Dir["#{@file_path}/sitemap_*.{xml,xml.gz}"].each do |file|
      FileUtils.rm file
    end
    return self
  end

  def generate
    for model, options in @sources
      with_sitemap(Extlib::Inflection::tableize(model.to_s)) do |sitemap|
        count_method = pick_method(model, COUNT_METHODS)
        find_method  = pick_method(model, FIND_METHODS)
        raise ArgumentError, "#{model} must provide a count_for_sitemap class method" if count_method.nil?
        raise ArgumentError, "#{model} must provide a find_for_sitemap class method" if find_method.nil?

        count        = model.send(count_method)
        num_sitemaps = 1
        num_batches  = 1

        if count > @options[:batch_size]
          num_batches  = (count.to_f / @options[:batch_size].to_f).ceil
          num_sitemaps = (count.to_f / @options[:max_per_sitemap].to_f).ceil
        end
        batches_per_sitemap = num_batches.to_f / num_sitemaps.to_f

        find_options = options.except(:path, :num_items, :priority, :change_frequency, :last_modified)

        for sitemap_num in 1..num_sitemaps
          # Work out the start and end batch numbers for this sitemap
          batch_num_start = sitemap_num == 1 ? 1 : ((sitemap_num * batches_per_sitemap).ceil - batches_per_sitemap + 1).to_i
          batch_num_end   = (batch_num_start + [batches_per_sitemap, num_batches].min).floor - 1

          for batch_num in batch_num_start..batch_num_end
            offset       = ((batch_num - 1) * @options[:batch_size])
            limit        = (count - offset) < @options[:batch_size] ? (count - offset - 1) : @options[:batch_size]
            find_options.update(:limit => limit, :offset => offset) if num_batches > 1

            model.send(find_method, find_options).each do |record|
              last_mod = options[:last_modified]
              if last_mod.is_a?(Proc)
                last_mod = last_mod.call(record)
              elsif last_mod.nil?
                last_mod_method = pick_method(record, TIMESTAMP_METHODS)
                last_mod = last_mod_method.nil? ? Time.now : record.send(last_mod_method)
              end

              param_method = pick_method(record, PARAM_METHODS)

              location = defined?(Rails) ? polymorphic_url(record) : nil rescue nil
              location ||= "#{root_url}/#{strip_leading_slash(options[:path])}/#{record.send(param_method)}"

              change_frequency = options[:change_frequency] || 'weekly'
              freq = change_frequency.is_a?(Proc) ? change_frequency.call(record) : change_frequency

              priority = options[:priority]
              pri = priority.is_a?(Proc) ? priority.call(record) : priority

              sitemap.add_url!(location, last_mod, freq, pri)
            end
          end
        end
      end
    end

    generate_sitemap_index

    return self
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
        $stderr.puts 'unable to ping Yahoo: no ":yahoo_app_id" provided'
      end
    end

    if @options[:ping_bing]
      Net::HTTP.get('www.bing.com', "/webmaster/ping.aspx?siteMap=#{sitemap_uri}")
    end

    if @options[:ping_ask]
      Net::HTTP.get('submissions.ask.com', "/ping?sitemap=#{sitemap_uri}")
    end
  end

  def root_url
    @root_url ||= begin
      url = ''
      url << (@default_url_options[:protocol] || 'http')
      url << '://' unless url.match('://')
      url << @default_url_options[:host]
      url << ":#{port}" if port = @default_url_options[:port] and port != 80
      url
    end
  end

  private

  def with_sitemap(name, options={})
    options[:filename] = "#{@file_path}/sitemap_#{name}"
    options[:max_urls] = @options[:max_per_sitemap]

    unless options[:gzip] = @options[:gzip]
      options[:indent] = 2
    end

    sitemap = Builder.new(options)

    begin
      yield sitemap
    ensure
      sitemap.close!
      @sitemap_files.concat sitemap.paths!
    end
  end

  def strip_leading_slash(str)
    str.sub(/^\//, '')
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
    if @options[:path].blank?
      "#{root_url}/#{File.basename(path)}"
    else
      "#{root_url}/#{@options[:path]}/#{File.basename(path)}"
    end
  end

  # Create a sitemap index document
  def generate_sitemap_index
    with_sitemap 'index', :type => 'index' do |sitemap|
      for path in @sitemap_files
        sitemap.add_url!(url_for_sitemap(path), File.stat(path).mtime)
      end
    end
  end
end