require 'rails_helper'

# Entrada por endereço (#1099, entrega B): só https, com prazo total e teto de bytes, e nunca para IP privado (o
# SafeFetch revalida cada redirecionamento).
RSpec.describe EmailCampaigns::Import::UrlSource, :aggregate_failures do
  def code_of(url)
    described_class.call(url)
    nil
  rescue EmailCampaigns::Import::Error => e
    e.code
  end

  it 'reads the page with the limits of a pasted model and keeps the address as the base' do
    calls = []
    allow(SafeFetch).to receive(:fetch) do |url, **options, &block|
      calls << [url, options]
      file = Tempfile.new('url-source-spec')
      file.write('<html><body><p>Novidades</p></body></html>')
      file.rewind
      block.call(SafeFetch::Result.new(tempfile: file, filename: 'x', content_type: 'text/html'))
    ensure
      file&.close!
    end

    result = described_class.call('https://news.example.com/ver?id=1')

    expect(result.markup).to include('Novidades')
    expect(result.base_url).to eq('https://news.example.com/ver?id=1')
    expect(calls.first.last).to include(schemes: ['https'], max_bytes: EmailCampaigns::Import::Limits::MAX_BYTES)
    expect(calls.first.last[:total_timeout]).to be_within(0.5).of(described_class::TIMEOUT_SECONDS)
    expect(calls.first.last[:allowed_content_type_prefixes]).to eq(['text/html'])
  end

  it 'uses the address the redirects ended at as the base, and keeps the charset the page answered with' do
    allow(SafeFetch).to receive(:fetch) do |_url, **_options, &block|
      file = Tempfile.new('url-source-spec', binmode: true)
      file.write('<p>Ver</p>')
      file.rewind
      block.call(SafeFetch::Result.new(tempfile: file, filename: 'x', content_type: 'text/html',
                                       url: 'https://view.news.example.com/c/42/', charset: 'iso-8859-1'))
    ensure
      file&.close!
    end

    result = described_class.call('https://news.example.com/ver?id=1')

    expect(result.base_url).to eq('https://view.news.example.com/c/42/')
    expect(result.charset).to eq('iso-8859-1')
  end

  it 'accepts only https addresses with a host' do
    expect(code_of('http://news.example.com/x')).to eq(:url_not_https)
    expect(code_of('ftp://news.example.com/x')).to eq(:url_not_https)
    expect(code_of('https://')).to eq(:url_invalid)
    expect(code_of('não é endereço')).to eq(:url_invalid)
    expect(code_of("https://example.com/#{'a' * 2100}")).to eq(:url_invalid)
    expect(code_of('https://user:senha@example.com/x')).to eq(:url_invalid)
  end

  it 'refuses a private address for real, without reaching it' do
    expect(code_of('https://127.0.0.1/modelo.html')).to eq(:url_unsafe)
    expect(code_of('https://169.254.169.254/latest/meta-data')).to eq(:url_unsafe)
    expect(code_of('https://10.0.0.5/modelo.html')).to eq(:url_unsafe)
  end

  it 'turns the network failures into codes the screen explains' do
    {
      SafeFetch::UnsafeUrlError.new('private') => :url_unsafe,
      SafeFetch::InvalidUrlError.new('scheme') => :url_not_https,
      SafeFetch::FileTooLargeError.new('big') => :too_large,
      SafeFetch::UnsupportedContentTypeError.new('pdf') => :url_not_html,
      SafeFetch::HttpError.new('404', status: 404) => :url_unreachable,
      SafeFetch::TotalTimeoutError.new('slow') => :url_unreachable
    }.each do |error, code|
      allow(SafeFetch).to receive(:fetch).and_raise(error)
      expect(code_of('https://news.example.com/x')).to eq(code)
    end
  end
end
