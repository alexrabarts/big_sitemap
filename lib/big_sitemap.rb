require 'uri'
require 'fileutils'

require 'big_sitemap/builder'

class BigSitemap
  DEFAULTS = {
    :max_per_sitemap => Builder::MAX_URLS,
    :batch_size      => 1001, # TODO: Deprecate
    :document_path   => '/',
    :gzip            => true,

    # Opinionated
    :ping_google => true,
    :ping_yahoo  => false, # needs :yahoo_app_id
    :ping_bing   => false,
    :ping_ask    => false, 
    :ping_yandex => false
  }

  # TODO: Deprecate
  COUNT_METHODS     = [:count_for_sitemap, :count]
  FIND_METHODS      = [:find_for_sitemap, :all]
  TIMESTAMP_METHODS = [:updated_at, :updated_on, :updated, :created_at, :created_on, :created]
  PARAM_METHODS     = [:to_param, :id]

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

    # TODO: Ddeprecate
    prepare_update

    add_urls

    # TODO: Deprecate
    generate_models
    generate_static

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

  # TODO: Deprecate
  def get_last_id(filename)
    Dir["#{filename}*.{xml,xml.gz}"].map do |file|
      file.to_s.scan(/#{filename}_(.+).xml/).flatten.last.to_i
    end.sort.last
  end

  private

  # TODO: Deprecate
  def table_name(model)
    model.table_name
  end

  # TODO: Deprecate
  def generate_models
    for model, options in @sources
      with_sitemap(options.dup.merge({:name => model})) do |sitemap|
        last_id = nil #id of last processed item
        count_method = pick_method(model, COUNT_METHODS)
        find_method  = pick_method(model, FIND_METHODS)
        raise ArgumentError, "#{model} must provide a count_for_sitemap class method" if count_method.nil?
        raise ArgumentError, "#{model} must provide a find_for_sitemap class method" if find_method.nil?

        find_options = {}
        [:conditions, :limit, :joins, :select, :order, :include, :group].each do |key|
          find_options[key] = options.delete(key)
        end

        # Keep the intial conditions for later user
        conditions = find_options[:conditions]

        primary_method   = options.delete(:primary_column)
        primary_column   = "#{table_name(model)}.#{primary_method}"

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
              find_options[:conditions] = [conditions, "(#{primary_column} > #{primary_column_value})"].compact.join(' AND ')
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

              change_frequency = options[:change_frequency]
              freq = change_frequency.is_a?(Proc) ? change_frequency.call(record) : change_frequency

              priority = options[:priority]
              pri = priority.is_a?(Proc) ? priority.call(record) : priority

              last_id = primary_column ? record.send(primary_method) : nil

              sitemap.add_url!(location, {
                :last_modified    => last_mod,
                :change_frequency => freq,
                :priority         => pri,
                :part_number      => last_id
              }) if location
            end
          end
        end
      end
    end
    self
  end

  # TODO: Deprecate
  def generate_static
    return self if Array(@static_pages).empty?
    with_sitemap({:name => 'static', :type => 'static'}) do |sitemap|
      @static_pages.each do |location, last_mod, freq, pri|
        sitemap.add_url!(location, {
          :last_modified    => last_mod,
          :change_frequency => freq,
          :priority         => pri
        })
      end
    end
    self
  end

  # TODO: Deprecate
  def prepare_update
    @files_to_move = []
    @sources.each do |model, options|
      if options[:partial_update] && (primary_column = options[:primary_column]) && (last_id = get_last_id(options[:filename]))
        primary_column_value       = escape_if_string last_id #escape '
        options[:conditions]       = [options[:conditions], "(#{table_name(model)}.#{primary_column} >= #{primary_column_value})"].compact.join(' AND ')
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

  # TODO: Deprecate
  def escape_if_string(value)
    (value.to_i.to_s == value.to_s) ?  value.to_i : "'#{value.gsub("'", %q(\\\'))}'"
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
