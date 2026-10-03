# frozen_string_literal: true

module Middleware
  class PrecompressedViteAssets
    VITE_ASSET_PREFIX = '/vite/assets/'
    CACHE_CONTROL = "public, max-age=#{1.year.to_i}"
    MIME_TYPES = {
      '.css' => 'text/css',
      '.js' => 'application/javascript',
      '.json' => 'application/json',
      '.svg' => 'image/svg+xml'
    }.freeze

    ENCODINGS = [
      ['br', '.br'],
      ['gzip', '.gz']
    ].freeze

    def initialize(app)
      @app = app
      @public_path = Rails.public_path.to_s
      @assets_root = File.expand_path(File.join(@public_path, VITE_ASSET_PREFIX))
    end

    def call(env)
      request_method = env['REQUEST_METHOD']
      return @app.call(env) unless request_method == 'GET' || request_method == 'HEAD'

      original_path = original_asset_path(env)
      return @app.call(env) unless original_path

      accepted_encoding(env).each do |encoding, extension|
        compressed_path = "#{original_path}#{extension}"
        next unless File.file?(compressed_path)

        return compressed_response(compressed_path, original_path, encoding, request_method)
      end

      @app.call(env)
    rescue StandardError
      @app.call(env)
    end

    private

    def original_asset_path(env)
      path = Rack::Utils.unescape_path(env['PATH_INFO'].to_s)
      return unless path.start_with?(VITE_ASSET_PREFIX)

      extension = File.extname(path)
      return unless MIME_TYPES.key?(extension)

      expanded_path = File.expand_path(File.join(@public_path, path))
      return unless expanded_path.start_with?(@assets_root)
      return unless File.file?(expanded_path)

      expanded_path
    end

    def accepted_encoding(env)
      header = env['HTTP_ACCEPT_ENCODING'].to_s
      encodings = header.split(',').filter_map do |part|
        encoding, *params = part.strip.split(';')
        next if refused?(params)

        encoding
      end

      ENCODINGS.select { |encoding, _extension| encodings.include?(encoding) }
    end

    # Sem parametro q a codificacao vale q=1 (RFC 9110); so q=0 recusa.
    def refused?(params)
      q_param = params.find { |param| param.strip.start_with?('q=') }
      return false unless q_param

      q_param.split('=', 2).last.to_f.zero?
    end

    def compressed_response(compressed_path, original_path, encoding, request_method)
      headers = {
        'Cache-Control' => CACHE_CONTROL,
        'Content-Encoding' => encoding,
        'Content-Length' => File.size(compressed_path).to_s,
        'Content-Type' => MIME_TYPES.fetch(File.extname(original_path)),
        'Vary' => 'Accept-Encoding'
      }
      body = request_method == 'HEAD' ? [] : [File.binread(compressed_path)]

      [200, headers, body]
    end
  end
end
