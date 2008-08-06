# GoogleRest
require 'open-uri'

class GoogleRest
  cattr_accessor :api_key
  cattr_accessor :referer

  API_VERSION = "1.0"
  API_URL = {
    :feed_lookup => "http://ajax.googleapis.com/ajax/services/feed/lookup",
    :feed_load => "http://ajax.googleapis.com/ajax/services/feed/load",
    :web => "http://ajax.googleapis.com/ajax/services/search/web",
    :blog => "http://ajax.googleapis.com/ajax/services/search/blogs"
  }

  def initialize
    path = File.join(RAILS_ROOT, "config/google_rest.yml")
    if !File.exists?(path)
      raise StandarError, "You must create config/google_rest.yml to use this plugin"
    else
      data = YAML.load_file(path)
      self.api_key = data['api_key'] if RAILS_ENV == 'production'
      self.referer = data['referer']
    end
  end

  def feed_lookup(website)
    url = API_URL[:feed_lookup] + "?q=#{CGI::escape(website.gsub(/^https?:\/\//i, ''))}"
    res = google_request(url)
    res.blank? ? nil : res["url"]
  end

  def feed_load(feed_url, count_entries = 10)
    url = API_URL[:feed_load] + "?num=#{count_entries}&q=#{CGI::escape(feed_url)}"
    res = google_request(url)
    res.blank? ? nil : res["feed"]
  end
  
  def blog_search(query, options = {})
    res = common_search( API_URL[:blog], "scoring=d&rsz=large&q=" + CGI::escape(query), options)
    (res.blank? || res["results"].blank?) ? [] : res["results"]
  end

  def web_search(query, options = {})
    res = common_search( API_URL[:web], "rsz=large&q=" + CGI::escape(query), options)
    (res.blank? || res["results"].blank?) ? [] : res["results"]
  end
  
  def inbound_links(url)
    res = common_search( API_URL[:web], CGI::escape("link:#{url.gsub(/^https?:\/\//,'')}"))
    (res.blank? || res["cursor"].blank?) ? 0 : res["cursor"]["estimatedResultCount"].to_i
  end
  
  def indexed_pages(url)
    res = common_search( API_URL[:web], CGI::escape("site:#{url.gsub(/^https?:\/\//,'')}"))
    (res.blank? || res["cursor"].blank?) ? 0 : res["cursor"]["estimatedResultCount"].to_i
  end
  
  private
  def common_search(base_url, init_query, options = {})
    query = []
    query << init_query unless init_query.blank?
    query << "&hl=#{options[:lang]}&lr=lang_#{options[:lang]}" unless options[:lang].blank?
    query << "&start=#{options[:start]}" unless options[:start].blank?
    google_request("#{base_url}?#{query.join('&')}")
  end

  def google_request(url)
    more = ["v=#{API_VERSION}"]
    more << "key=#{self.api_key}" unless self.api_key.blank?
    uri = URI.parse("#{url}&#{more.join('&')}") rescue uri = nil
    return if uri.blank?

    logger.debug "Google Request: #{uri.to_s}"
    http = Net::HTTP.new(uri.host, uri.port)
    response = http.request_get(uri.request_uri, {'Referer' => self.referer})
    res = response.body

    unless res.blank?
      data = ActiveSupport::JSON.decode(res) rescue data = nil
      if data.is_a?(Hash) && data["responseData"].is_a?(Hash)
        Util.json_recursive_unescape(data["responseData"])
      end
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
