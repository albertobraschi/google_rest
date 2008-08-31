class GoogleRest
  if defined?(HTTParty)
    include HTTParty
    base_uri "http://ajax.googleapis.com/ajax/services"
    format :json
  end

  attr_accessor :api_key
  attr_accessor :referer

  @@ascii_available = "".respond_to?(:to_ascii)
  
  API_VERSION = "1.0"
  API_URL = {
    :feed_lookup => "/feed/lookup",
    :feed_load => "/feed/load",
    :web => "/search/web",
    :blog => "/search/blogs"
  }

  def initialize
    path = File.join(RAILS_ROOT, "config/google_rest.yml")
    if !File.exists?(path)
      raise StandardError, "You must create config/google_rest.yml to use this plugin"
    else
      data = YAML.load_file(path)
      self.api_key = data['api_key'] if RAILS_ENV == 'production'
      self.referer = data['referer']
    end
  end

  def feed_lookup(website)
    res = google_request(:feed_lookup, {:q => website.gsub(/^https?:\/\//i, '')})
    res.blank? ? nil : res["url"]
  end

  def feed_load(feed_url, count_entries = 10)
    res = google_request(:feed_load, {:num => count_entries, :q => feed_url, :scoring => 'h'} )
    res.blank? ? nil : res["feed"]
  end

  def tagcloud(feed_url, count_entries = 100)
    res = google_request(:feed_load, {:num => count_entries, :q => feed_url, :scoring => 'h', :no_escape => true} )
    if res.blank? or res["feed"].blank? or res["feed"]["entries"].blank?
      return {}
    end
    
    res["feed"]["entries"].collect {|e|e["categories"]}.flatten.inject({}) do |hsh, str|
      next if str.blank?
      str = (@@ascii_available ? str.to_ascii : str).downcase
      hsh[str] ||= 0
      hsh[str] += 1
      hsh
    end.to_a.collect {|e|e[1]>1 ? [e[0], e[1]] : nil}.compact.sort {|a,b| b[1]<=>a[1]}
  end

  def blog_search(query, options = {})
    res = common_search(:blog, {:scoring => 'd', :rsz => 'large', :q => query}.merge(options))
    (res.blank? || res["results"].blank?) ? [] : res["results"]
  end

  def web_search(query, options = {})
    res = common_search(:web, {:rsz => 'large', :q => query}.merge(options))
    (res.blank? || res["results"].blank?) ? [] : res["results"]
  end

  def inbound_links(url)
    res = common_search(:web, {:q => "link:#{url.gsub(/^https?:\/\//,'')}"})
    (res.blank? || res["cursor"].blank?) ? 0 : res["cursor"]["estimatedResultCount"].to_i
  end

  def indexed_pages(url)
    res = common_search(:web, {:q => "site:#{url.gsub(/^https?:\/\//,'')}"})
    (res.blank? || res["cursor"].blank?) ? 0 : res["cursor"]["estimatedResultCount"].to_i
  end

  private
  def common_search(type, query = {})
    if !(lang=query.delete(:lang)).blank?
      lang.downcase!
      query[:hl] = lang
      query[:lr] = "lang_#{lang}"
    end
    google_request(type, query)
  end

  def google_request(type, query = {})
    no_escape = query.delete(:no_escape)
    query[:v] = API_VERSION
    query[:key] = api_key unless api_key.blank?
    self.class.headers({'Referer' => self.referer})
    res = self.class.get(API_URL[type], :query => query)
    if res.is_a?(Hash) && res["responseData"].is_a?(Hash)
      no_escape ? res["responseData"] : Util.json_recursive_unescape(res["responseData"])
    else
      nil
    end
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
