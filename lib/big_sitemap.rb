require 'net/http'
require 'uri'
require 'zlib'
require 'builder'
require 'extlib'

class BigSitemap
  def initialize(options)
    document_root = options.delete(:document_root)

    if document_root.nil?
      if defined? RAILS_ROOT
        document_root = "#{RAILS_ROOT}/public"
      elsif defined? Merb
        document_root = "#{Merb.root}/public"
      end
    end

    raise ArgumentError, 'Document root must be specified with the :document_root option' if document_root.nil?

    @base_url        = options.delete(:base_url)
    @max_per_sitemap = options.delete(:max_per_sitemap) || 50000
    @batch_size      = options.delete(:batch_size) || 1001 # TODO: Set this to 1000 once DM offset 37000 bug is fixed
    @web_path        = options.delete(:path) || 'sitemaps'
    @ping_google     = options[:ping_google].nil? ? true : options.delete(:ping_google)
    @ping_yahoo      = options[:ping_yahoo].nil? ? true : options.delete(:ping_yahoo)
    @yahoo_app_id    = options.delete(:yahoo_app_id)
    @ping_msn        = options[:ping_msn].nil? ? true : options.delete(:ping_msn)
    @ping_ask        = options[:ping_ask].nil? ? true : options.delete(:ping_ask)
    @file_path       = "#{document_root}/#{@web_path}"
    @sources         = []

    raise ArgumentError, "Base URL must be specified with the :base_url option" if @base_url.nil?

    raise(
      ArgumentError,
      'Batch size (:batch_size) must be less than or equal to maximum URLs per sitemap (:max_per_sitemap)'
    ) if @batch_size > @max_per_sitemap

    Dir.mkdir(@file_path) unless File.exists? @file_path
  end

  def add(options)
    raise ArgumentError, ':model and :path options must be provided' unless options[:model] && options[:path]
    @sources << options
  end

  def clean
    unless @file_path.nil?
      Dir.foreach(@file_path) do |f|
        f = "#{@file_path}/#{f}"
        File.delete(f) if File.file?(f)
      end
    end
  end

  def generate
    @sources.each do |source|
      klass = source[:model]

      count_method = pick_method(klass, [:count_for_sitemap, :count])
      find_method  = pick_method(klass, [:find_for_sitemap, :all])
      raise ArgumentError, "#{klass} must provide a count_for_sitemap class method" if count_method.nil?
      raise ArgumentError, "#{klass} must provide a find_for_sitemap class method" if find_method.nil?

      count        = klass.send(count_method)
      num_sitemaps = 1
      num_batches  = 1

      if count > @batch_size
        num_batches  = (count.to_f / @batch_size.to_f).ceil
        num_sitemaps = (count.to_f / @max_per_sitemap.to_f).ceil
      end
      batches_per_sitemap = num_batches.to_f / num_sitemaps.to_f

      # Update the @sources hash so that the index file knows how many sitemaps to link to
      source[:num_sitemaps] = num_sitemaps

      for sitemap_num in 1..num_sitemaps
        # Work out the start and end batch numbers for this sitemap
        batch_num_start = sitemap_num == 1 ? 1 : ((sitemap_num * batches_per_sitemap).ceil - batches_per_sitemap + 1).to_i
        batch_num_end   = (batch_num_start + [batches_per_sitemap, num_batches].min).floor - 1

        # Stream XML output to a file
        filename = "sitemap_#{Extlib::Inflection::underscore(klass.to_s)}"
        filename << "_#{sitemap_num}" if num_sitemaps > 1

        gz = gz_writer("#{filename}.xml.gz")

        xml = Builder::XmlMarkup.new(:target => gz)
        xml.instruct!
        xml.urlset(:xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9') do
          for batch_num in batch_num_start..batch_num_end
            offset       = ((batch_num - 1) * @batch_size)
            limit        = (count - offset) < @batch_size ? (count - offset - 1) : @batch_size
            find_options = num_batches > 1 ? {:limit => limit, :offset => offset} : {}

            klass.send(find_method, find_options).each do |r|
              last_mod_method = pick_method(
                r,
                [:updated_at, :updated_on, :updated, :created_at, :created_on, :created]
              )
              last_mod = last_mod_method.nil? ? Time.now : r.send(last_mod_method)

              param_method = pick_method(r, [:to_param, :id])
              raise ArgumentError, "#{klass} must provide a to_param instance method" if param_method.nil?

              xml.url do
                xml.loc("#{@base_url}/#{source[:path]}/#{r.send(param_method)}")
                xml.lastmod(last_mod.strftime('%Y-%m-%d')) unless last_mod.nil?
                xml.changefreq('weekly')
              end
            end
          end
        end

        gz.close
      end

    end

    generate_sitemap_index
    ping_search_engines
  end

  private
    def pick_method(klass, candidates)
      method = nil
      candidates.each do |candidate|
        if klass.respond_to? candidate
          method = candidate
          break
        end
      end
      method
    end

    def gz_writer(filename)
      Zlib::GzipWriter.new(File.open("#{@file_path}/#{filename}", 'w+'))
    end

    def sitemap_index_filename
      'sitemap_index.xml.gz'
    end

    # Create a sitemap index document
    def generate_sitemap_index
      xml     = ''
      builder = Builder::XmlMarkup.new(:target => xml)
      builder.instruct!
      builder.sitemapindex(:xmlns => 'http://www.sitemaps.org/schemas/sitemap/0.9') do
        @sources.each do |source|
          num_sitemaps = source[:num_sitemaps]
          for i in 1..num_sitemaps
            loc = "#{@base_url}/#{@web_path}/sitemap_#{Extlib::Inflection::underscore(source[:model].to_s)}"
            loc << "_#{i}" if num_sitemaps > 1
            loc << '.xml.gz'

            builder.sitemap do
              builder.loc(loc)
              builder.lastmod(Time.now.strftime('%Y-%m-%d'))
            end
          end
        end
      end

      gz = gz_writer(sitemap_index_filename)
      gz.write(xml)
      gz.close
    end

    def sitemap_uri
      URI.escape("#{@base_url}/#{@web_path}/#{sitemap_index_filename}")
    end

    # Notify Google of the new sitemap index file
    def ping_google
      Net::HTTP.get('www.google.com', "/webmasters/tools/ping?sitemap=#{sitemap_uri}")
    end

    # Notify Yahoo! of the new sitemap index file
    def ping_yahoo
      Net::HTTP.get('search.yahooapis.com', "/SiteExplorerService/V1/updateNotification?appid=#{@yahoo_app_id}&url=#{sitemap_uri}")
    end

    # Notify MSN of the new sitemap index file
    def ping_msn
      Net::HTTP.get('webmaster.live.com', "/ping.aspx?siteMap=#{sitemap_uri}")
    end

    # Notify Ask of the new sitemap index file
    def ping_ask
      Net::HTTP.get('submissions.ask.com', "/ping?sitemap=#{sitemap_uri}")
    end

    def ping_search_engines
      ping_google if @ping_google
      ping_yahoo if @ping_yahoo && @yahoo_app_id
      ping_msn if @ping_msn
      ping_ask if @ping_ask
    end
end