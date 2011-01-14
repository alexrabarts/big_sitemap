require 'fileutils'
require 'zlib'

class BigSitemap
  class Builder
    MAX_URLS = 50000
    HEADER_ATTRIBUTES = {
      'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9',
      'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance",
      'xsi:schemaLocation' => "http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd" 
    }

    def initialize(options)
      @gzip           = options.delete(:gzip)
      @max_urls       = options.delete(:max_urls) || MAX_URLS
      @type           = options.delete(:type)
      @paths          = []
      @parts          = options.delete(:start_part_id) || 0
      @custom_part_nr = options.delete(:partial_update)

      @filename = options.delete(:filename)
      @current_filename = nil
      @tmp_filename     = nil
      @target = _get_writer

      @level = 0
      @opened_tags = []
      _init_document
    end

    def add_url!(url, time = nil, frequency = nil, priority = nil, part_nr = nil)
      _rotate(part_nr) if @max_urls == @urls

      _open_tag 'url'
      tag! 'loc', url
      tag! 'lastmod', time.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00') if time
      tag! 'changefreq', frequency if frequency
      tag! 'priority', priority if priority
      _close_tag 'url'

      @urls += 1
    end

    def paths!
      @paths
    end

    def close!
      _close_document
      target!.close if target!.respond_to?(:close)
      File.delete(@current_filename) if File.exists?(@current_filename)
      File.rename(@tmp_filename, @current_filename)
    end

    def target!
      @target
    end

    private

    def _get_writer
      filename = @filename.dup
      filename << "_#{@parts}" if @parts > 0
      filename << '.xml'
      filename << '.gz' if @gzip
      _open_writer(filename)
    end

    def _open_writer(filename)
      @current_filename = filename
      @tmp_filename     = filename + ".tmp"
      @paths << filename
      file = ::File.open(@tmp_filename, 'w+')
      @gzip ? ::Zlib::GzipWriter.new(file) : file
    end

    def _init_document( name = 'urlset', attrs = HEADER_ATTRIBUTES)
      @urls = 0
      target!.print '<?xml version="1.0" encoding="UTF-8"?>'
      _newline
      _open_tag name, attrs
    end

    def _rotate(part_nr = nil)
      # write out the current document and start writing into a new file
      close!
      @parts = (part_nr && @custom_part_nr) ? part_nr : @parts + 1
      @target = _get_writer
      _init_document
    end

    # opens a tag, bumps up level but doesn't require a block
    def _open_tag(name, attrs = {})
      _indent
      _start_tag(name, attrs)
      _newline
      @level += 1
      @opened_tags << name
    end

    def _start_tag(name, attrs = {})
      attrs = attrs.map { |attr,value| %Q( #{attr}="#{value}") }.join('')
      target!.print "<#{name}#{attrs}>"
    end

    def tag!(name, content, attrs = {})
      _indent
      _start_tag(name, attrs)
      target!.print content.to_s.gsub('&', '&amp;')
      _end_tag(name)
      _newline
    end

    def _end_tag(name)
      target!.print "</#{name}>"
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

    def _indent
      return if @gzip
      target!.print "  " * @level
    end

    def _newline
      return if @gzip
      target!.puts ''
    end
  end

  class IndexBuilder < Builder
    def _init_document(name = 'sitemapindex', attrs = {'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9'})
      attrs.merge('xmlns:geo' => "http://www.google.com/geo/schemas/sitemap/1.0")
      super(name, attrs)
    end

    def add_url!(url, time = nil)
      _open_tag 'sitemap'
      tag! 'loc', url
      tag! 'lastmod', time.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00') if time
      _close_tag 'sitemap'
    end
  end

  class GeoBuilder < Builder
    #_build_geo if @geo

    # def _build_geo
    #   geo :geo do
    #     geo :format, 'kml'
    #   end
    # end
  end

end
