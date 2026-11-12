require 'rails_helper'

# `proxy:` (#2942): o pedido sai pelo proxy (o Net::HTTP recebe endereço, porta e credencial, e nunca o do ambiente). Sem
# a opção, nada muda. A credencial nunca aparece no inspect.
RSpec.describe SafeFetch::RequestOptions do
  let(:proxy) { SafeFetch::Proxy.new(address: '203.0.113.11', port: 6000, user: 'usuario-secreto', password: 'senha-secreta') }

  it 'passes the proxy to Net::HTTP, never the one from the environment' do
    options = described_class.new(url: 'https://example.com/a.json', proxy: proxy, schemes: %w[https], max_retries: 0)

    expect(options.request_options[:http_options]).to include(
      proxy_from_env: false, proxy_address: '203.0.113.11', proxy_port: 6000, proxy_user: 'usuario-secreto',
      proxy_pass: 'senha-secreta', max_retries: 0
    )
  end

  it 'leaves the connection as it was without a proxy' do
    http_options = described_class.new(url: 'https://example.com/a.json').request_options[:http_options]

    expect(http_options.keys).to contain_exactly(:open_timeout, :read_timeout)
  end

  it 'refuses a proxy unless the url and every hop are https (over http the proxy would resolve the name: SSRF)' do
    [{ url: 'https://example.com/a.json' }, { url: 'https://example.com/a.json', schemes: %w[http https] },
     { url: 'http://example.com/a.json', schemes: %w[https] }].each do |pedido|
      expect { described_class.new(**pedido, proxy: proxy) }.to raise_error(ArgumentError)
    end
  end

  it 'never shows the proxy credential' do
    options = described_class.new(url: 'https://example.com/a.json', proxy: proxy, schemes: %w[https])

    [proxy.inspect, proxy.to_s, options.inspect].each do |texto|
      expect(texto).not_to include('usuario-secreto')
      expect(texto).not_to include('senha-secreta')
    end
  end
end
