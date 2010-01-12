require 'builder'
require 'zlib'

class BigSitemap
  class Builder < Builder::XmlMarkup
    MAX_URLS = 50000

    def initialize(options)
      @gzip = options.delete(:gzip)
      @max_urls = options.delete(:max_urls) || MAX_URLS
      @type = options.delete(:type)
      @geo  = options.delete(:geo)
      @paths = []
      @parts = 0

      if @filename = options.delete(:filename)
        options[:target] = _get_writer
      end

      super(options)

      @opened_tags = []
      _init_document
    end

    def index?
      @type == 'index'
    end

    def geo?
      !index? && @geo == true
    end

    def add_url!(url, time = nil, frequency = nil, priority = nil)
      _rotate if @max_urls == @urls

      tag!(index? ? 'sitemap' : 'url') do
        loc (geo? ? "#{url}.kml" : url)
        # W3C format is the subset of ISO 8601
        lastmod(time.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00')) unless time.nil?
        changefreq(frequency) unless frequency.nil?
        priority(priority) unless priority.nil?
        _build_geo if geo?
      end
      @urls += 1
    end

    def close!
      _close_document
      target!.close if target!.respond_to?(:close)
    end

    def paths!
      @paths
    end

    private

    def _get_writer
      if @filename
        filename = @filename.dup
        filename << "_#{@parts}" if @parts > 0
        filename << '.xml'
        filename << '.gz' if @gzip
        _open_writer(filename)
      else
        target!
      end
    end

    def _open_writer(filename)
      file = File.open(filename, 'w+')
      @paths << filename
      @gzip ? Zlib::GzipWriter.new(file) : file
    end

    def _init_document
      @urls = 0
      instruct!
      # define root element and namespaces
      attrs = {'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9'}
      attrs['xmlns:geo'] = "http://www.google.com/geo/schemas/sitemap/1.0" if geo?
      _open_tag(index? ? 'sitemapindex' : 'urlset', attrs)
    end

    def _rotate
      # write out the current document and start writing into a new file
      close!
      @parts += 1
      @target = _get_writer
      _init_document
    end

    # add support for:
    #   xml.open_foo!(attrs)
    #   xml.close_foo!
    def method_missing(method, *args, &block)
      if method.to_s =~ /^(open|close)_(.+)!$/
        operation, name = $1, $2
        name = "#{name}:#{args.shift}" if Symbol === args.first

        if 'open' == operation
          _open_tag(name, args.first)
        else
          _close_tag(name)
        end
      else
        super
      end
    end

    # opens a tag, bumps up level but doesn't require a block
    def _open_tag(name, attrs)
      _indent
      _start_tag(name, attrs)
      _newline
      @level += 1
      @opened_tags << name
    end

    # closes a tag block by decreasing the level and inserting a close tag
    def _close_tag(name)
      @opened_tags.pop
      @level -= 1
      _indent
      _end_tag(name)
      _newline
    end

    def _close_document
      for name in @opened_tags.reverse
        _close_tag(name)
      end
    end

    def _build_geo
      geo :geo do
        geo :format, 'kml'
      end
    end

  end
end
