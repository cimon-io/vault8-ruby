# frozen_string_literal: true

require 'vault8/version'
require 'json'
require 'uri'
require 'net/http'
require 'net/http/post/multipart'
require 'digest'
require 'tempfile'

# Vault8 is a class providing interface to handle file uploads.
class Vault8
  attr_reader :public_key, :secret_key, :service_url

  def self.create!(public_key:, secret_key:, service_url:)
    new(public_key, secret_key, service_url)
  end

  def initialize(public_key, secret_key, service_url)
    @public_key = public_key
    @secret_key = secret_key
    @service_url = service_url
  end

  def image_url(uid:, filters: [], image_name: 'image.jpg', current_time: nil, until_time: nil)
    generate_url_for(path: image_path(uid, filters, image_name),
                     current_time: (current_time && current_time.to_i),
                     until_time: (until_time && until_time.to_i))
  end

  def upload_url(path: '/upload', current_time: Time.now, until_time: Time.now + 86_400)
    generate_url_for(path: path, current_time: current_time.to_i, until_time: until_time.to_i)
  end

  def encode_token(path:, current_time: nil, until_time: nil)
    Digest::SHA1.hexdigest([public_key, secret_key, path, current_time, until_time].compact.join('|')).reverse
  end

  def image_path(uid, filters = [], image_name = 'image.jpg')
    '/' + [uid, merged_filters(filters), escape(escape(image_name), '[]')].compact.join('/')
  end

  def merged_filters(filters = [])
    return nil if filters.empty?

    filters.flat_map do |filter|
      filter.map do |k, v|
        [k, v.to_s.empty? ? nil : v].compact.join('-')
      end
    end.join(',')
  end

  def generate_url_for(path:, current_time: nil, until_time: nil)
    path = escape(path)
    uri = URI.join(service_url, path)
    uri.query = {
      p: public_key,
      s: encode_token(path: path, current_time: current_time, until_time: until_time),
      time: current_time,
      until: until_time
    }.each_with_object([]) { |(k, v), acc| acc << "#{k}=#{v}" unless v.nil? }.join('&')

    uri.to_s
  end

  def upload_image(file)
    options = if file.is_a?(String)
                { url: file }
              elsif file.respond_to?(:tempfile)
                { file: file }
              elsif file.is_a?(File) || file.is_a?(Tempfile)
                { file: File.new(file) }
              end

    JSON.parse(post_request(options))
  rescue JSON::ParserError
    { 'response' => 'error' }
  end

  private

  def post_request(options = {})
    return post_link(options) if options[:url]

    post_file(options)
  end

  # TODO: handle failed response?
  def post_link(url:)
    Net::HTTP.post_form(upload_uri, url: url).body
  end

  def post_file(file:, use_ssl: true)
    Net::HTTP.start(upload_uri.host, upload_uri.port, use_ssl: use_ssl) do |http|
      file = UploadIO.new(file, mime_for_file(file), file.path)
      request = Net::HTTP::Post::Multipart.new(upload_uri.request_uri, file: file)
      http.request(request).body
    end
  end

  # TODO: add real mime-type check
  def mime_for_file(file)
    "image/#{File.extname(file)[1..]}"
  end

  def upload_uri
    URI(upload_url)
  end

  # https://github.com/ruby/ruby/blob/master/lib/uri/common.rb#L100-L104
  def escape(*args)
    URI::DEFAULT_PARSER.escape(*args)
  end
end
