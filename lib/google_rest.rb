require 'json/add/rails'

module GoogleRest
  PER_PAGE = 8
  
  class Response

    attr_accessor :raw, :results, :cursor

    def initialize(raw)
      self.raw = raw
      data = (raw || {})
      self.cursor = data["cursor"]
      self.results = data["results"] || []
    end

    def empty?
      raw.blank?
    end
    
    def each
      results.each { |r| yield r }
    end
    
    def map
      results.map { |r| yield r }
    end
    
    def page
      cursor["currentPageIndex"].blank? ? 1 : cursor["currentPageIndex"]
    end
    
    def pages
      (cursor["pages"] || [])
    end
    
    def total_pages
      (cursor["pages"] || []).length
    end
    
    def total_entries
      if pages.last
        pages.last["start"].to_i + GoogleRest::PER_PAGE - 1
      else
        0
      end
    end
    
    def per_page
      8
    end
    
    def paginated(current_page = nil)
      results.paginate(:page => current_page || page, :per_page => per_page, :total_entries => total_entries)
    end
    
  end

  class Request
    if defined?(HTTParty)
      include HTTParty
      base_uri "http://ajax.googleapis.com/ajax/services"
      format :html
    end

    attr_accessor :api_key
    attr_accessor :referer

    @@ascii_available = "".respond_to?(:to_ascii)

    API_VERSION = "1.0"
    API_URL = {
      :feed_lookup => "/feed/lookup",
      :feed_load => "/feed/load",
      :web => "/search/web",
      :blog => "/search/blogs",
      :news => "/search/news"
    }

    def initialize
      path = File.join(RAILS_ROOT, "config/google_rest.yml")
      if !File.exists?(path)
        raise StandardError, "You must create config/google_rest.yml to use this plugin"
      else
        data = YAML.load_file(path) || {}
        self.api_key = data['api_key'] if RAILS_ENV == 'production'
        self.referer = data['referer']
      end
    end

    def feed_lookup(website)
      return nil if website.blank?
      res = google_request(:feed_lookup, {:q => website.to_s.gsub(/^https?:\/\//i, '')})
      res.empty? ? nil : res.raw["url"]
    end

    def feed_load(feed_url, count_entries = false)
      return nil if feed_url.blank?
      if count_entries == false
        # we retrieve the current feed entries
        res = google_request(:feed_load, {:q => feed_url, :num => -1})
      else
        res = google_request(:feed_load, {:num => count_entries, :q => feed_url, :scoring => 'h'} )
      end
      res.empty? ? nil : res.raw["feed"]
    end

    def blog_search(query, options = {})
      common_search(:blog, {:scoring => 'd', :rsz => 'large', :q => query}.merge(options))
    end

    def web_search(query, options = {})
      common_search(:web, {:rsz => 'large', :q => query}.merge(options))
    end

    def news_search(query, options = {})
      common_search(:news, {:rsz => 'large', :scoring => 'd', :q => query}.merge(options))
    end

    def inbound_links(url)
      res = common_search(:web, {:q => "link:#{url.gsub(/^https?:\/\//,'')}"})
      res.cursor.blank? ? 0 : res.cursor["estimatedResultCount"].to_i
    end

    def indexed_pages(url)
      res = common_search(:web, {:q => "site:#{url.gsub(/^https?:\/\//,'')}"})
      res.cursor.blank? ? 0 : res.cursor["estimatedResultCount"].to_i
    end

    private
    def common_search(type, query = {})
      if !(lang=query.delete(:lang)).blank?
        lang.downcase!
        if type == :news
          query[:hl] = lang
          query[:ned] = lang
        else
          query[:hl] = lang
          query[:lr] = "lang_#{lang}"
        end
      end
      google_request(type, query)
    end

    def google_request(type, query = {})
      # HTTParty now use JSON instead of ActiveSupport::JSON to do the decoding
      # But it doesn't seems to work with Google Results so we hack it to not parse
      # google results and we decode them by ourselves
      no_escape = query.delete(:no_escape)
      query[:v] = API_VERSION
      query[:key] = api_key unless api_key.blank?
      self.class.headers({'Referer' => self.referer})
      res = self.class.get(API_URL[type], :query => query)
      res = ActiveSupport::JSON.decode(res)
      if res.is_a?(Hash) && res["responseData"].is_a?(Hash)
        GoogleRest::Response.new(no_escape ? res["responseData"] : Util.json_recursive_unescape(res["responseData"]))
      else
        GoogleRest::Response.new(nil)
      end
    rescue ActiveSupport::JSON::ParseError
      GoogleRest::Response.new(nil)
    end

    def logger
      @logger ||= defined?(RAILS_DEFAULT_LOGGER) ? RAILS_DEFAULT_LOGGER : Logger.new(STDOUT)
    end

    module Util
      JSON_ESCAPE = { '&' => '\u0026', '>' => '\u003E', '<' => '\u003C', '=' => '\u003D' }

      # A utility method for unescaping HTML entities in JSON strings.
      #   puts json_unescape("\u003E 0 \u0026 a \u003C 10?")
      #   # => is a > 0 & a < 10?
      def json_unescape(s)
        JSON_ESCAPE.inject(s.to_s) { |str, (k,v)| str.gsub!(/#{Regexp.escape(v)}/i, k); str }
      end

      # A utility method for escaping HTML entities in JSON strings.
      #   puts json_escape("is a > 0 & a < 10?")
      #   # => is a \u003E 0 \u0026 a \u003C 10?
      def json_escape(s)
        s.to_s.gsub(/[&"><]/) { |special| JSON_ESCAPE[special] }
      end

      # A utility method for unescaping recursively HTML entities in JSON array or hash.
      def json_recursive_unescape(data)
        case data
        when String : json_unescape(data)
        when Hash : data.inject({}) { |hsh, (k,v)| hsh[k] = json_recursive_unescape(v);hsh }
        when Array : data.collect { |v| json_recursive_unescape(v) }
        end
      end

      module_function :json_escape
      module_function :json_unescape
      module_function :json_recursive_unescape
    end
  end
end
