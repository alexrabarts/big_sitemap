require 'fileutils'
require 'zlib'

class BigSitemap
  class Builder
    MAX_URLS = 50000
    HEADER_NAME = 'urlset'
    HEADER_ATTRIBUTES = {
      'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9',
      'xmlns:video' => "http://www.google.com/schemas/sitemap-video/1.1",
      'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance",
      'xsi:schemaLocation' => "http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd"
    }

    # as per http://support.google.com/webmasters/bin/answer.py?hl=en&answer=80472#1
    VIDEO_ATTRIBUTES = %w(thumbnail_loc title description content_loc player_loc duration expiration_date rating view_count
                          publication_date family_friendly restriction gallery_loc price requires_subscription uploader platform live)

    def initialize(options)
      @gzip           = options.delete(:gzip)
      @max_urls       = options.delete(:max_urls) || MAX_URLS
      @type           = options.delete(:type)
      @filepaths      = []
      @parts          = options.delete(:start_part_id) || 0
      @partial_update = options.delete(:partial_update)

      @filename         = options.delete(:filename)
      @current_filename = nil
      @tmp_filename     = nil
      @target           = _get_writer

      @level = 0
      @opened_tags = []
      _init_document
    end

    def add_url!(location, options={})
      _rotate(options[:id]) if @max_urls == @urls
      _open_tag 'url'

      tag! 'loc', location
      tag! 'lastmod', options[:last_modified].utc.strftime('%Y-%m-%dT%H:%M:%S+00:00') if options[:last_modified]
      tag! 'changefreq', options[:change_frequency] || 'weekly'
      tag! 'priority', options[:priority] if options[:priority]

      if options[:video]
        _open_tag 'video:video'

          options[:video].each do |attribute, value_or_hash|
            if value_or_hash.is_a?(Hash)
              tag_value = value_or_hash.delete(:value)
              opts      = value_or_hash
            else
              tag_value = value_or_hash
              opts      = {}
            end

            tag_value = tag_value.utc.strftime('%Y-%m-%dT%H:%M:%S+00:00') if attribute.to_s[0..-5] == "_date"

            tag! "video:#{attribute}", tag_value, opts
          end

        _close_tag 'video:video'
      end

      _close_tag 'url'

      @urls += 1
    end

    def filepaths!
      @filepaths
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
      filename << "_#{@parts}" if @parts > 0 && @type != 'index'
      filename << '.xml'
      filename << '.gz' if @gzip
      _open_writer(filename)
    end

    def _open_writer(filename)
      @current_filename = filename
      @tmp_filename     = filename + ".tmp"
      @filepaths << filename
      file = ::File.open(@tmp_filename, 'w+:ASCII-8BIT')
      @gzip ? ::Zlib::GzipWriter.new(file) : file
    end

    def _init_document
      @urls = 0
      target!.print '<?xml version="1.0" encoding="UTF-8"?>'
      _newline
      _open_tag self.class::HEADER_NAME, self.class::HEADER_ATTRIBUTES
    end

    def _rotate(part_nr=nil)
      # write out the current document and start writing into a new file
      close!
      @parts = part_nr || @parts + 1
      @target = _get_writer
      _init_document
    end

    # opens a tag, bumps up level but doesn't require a block
    def _open_tag(name, attrs={})
      _indent
      _start_tag(name, attrs)
      _newline
      @level += 1
      @opened_tags << name
    end

    def _start_tag(name, attrs={})
      attrs = attrs.map { |attr, value| %Q( #{attr}="#{value}") }.join('')
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
      target!.print "  " * @level
    end

    def _newline
      target!.puts ''
    end
  end

  class IndexBuilder < Builder
    HEADER_NAME = 'sitemapindex'
    HEADER_ATTRIBUTES = {
      'xmlns' => 'http://www.sitemaps.org/schemas/sitemap/0.9'
    }

    def add_url!(location, options={})
      _open_tag 'sitemap'

      tag! 'loc', location
      tag! 'lastmod', options[:last_modified].utc.strftime('%Y-%m-%dT%H:%M:%S+00:00') if options[:last_modified]

      _close_tag 'sitemap'
    end
  end


end
