# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('lib/middleware/precompressed_vite_assets')

RSpec.describe Middleware::PrecompressedViteAssets do
  let(:fallback_app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['fallback']] } }
  let(:app) { described_class.new(fallback_app) }
  let(:asset_dir) { Rails.public_path.join('vite/assets') }
  let(:asset_name) { "precompressed-test-#{SecureRandom.hex(6)}.js" }
  let(:asset_path) { asset_dir.join(asset_name) }

  before do
    FileUtils.mkdir_p(asset_dir)
    File.binwrite(asset_path, 'console.log("source");')
    File.binwrite("#{asset_path}.br", 'brotli')
    File.binwrite("#{asset_path}.gz", 'gzip')
  end

  after do
    [asset_path, "#{asset_path}.br", "#{asset_path}.gz"].each do |path|
      FileUtils.rm_f(path)
    end
  end

  it 'serves Brotli assets when the client accepts br' do
    status, headers, body = request_with_encoding('br, gzip')

    expect(status).to eq(200)
    expect(headers['Content-Encoding']).to eq('br')
    expect(headers['Vary']).to eq('Accept-Encoding')
    expect(headers['Content-Type']).to eq('application/javascript')
    expect(body.join).to eq('brotli')
  end

  it 'serves Gzip assets when Brotli is not accepted' do
    status, headers, body = request_with_encoding('gzip')

    expect(status).to eq(200)
    expect(headers['Content-Encoding']).to eq('gzip')
    expect(body.join).to eq('gzip')
  end

  it 'does not serve Brotli assets when Brotli is explicitly refused' do
    status, headers, body = request_with_encoding('br;q=0, gzip')

    expect(status).to eq(200)
    expect(headers['Content-Encoding']).to eq('gzip')
    expect(body.join).to eq('gzip')
  end

  it 'falls back to the next middleware without accepted encoding' do
    status, headers, body = request_with_encoding(nil)

    expect(status).to eq(200)
    expect(headers['Content-Encoding']).to be_nil
    expect(body.join).to eq('fallback')
  end

  it 'does not serve paths outside public vite assets' do
    env = Rack::MockRequest.env_for(
      '/vite/assets/%2e%2e/secret.js',
      method: 'GET',
      'HTTP_ACCEPT_ENCODING' => 'br'
    )

    status, _headers, body = app.call(env)

    expect(status).to eq(200)
    expect(body.join).to eq('fallback')
  end

  def request_with_encoding(encoding)
    headers = encoding ? { 'HTTP_ACCEPT_ENCODING' => encoding } : {}
    env = Rack::MockRequest.env_for("/vite/assets/#{asset_name}", { method: 'GET' }.merge(headers))
    app.call(env)
  end
end
