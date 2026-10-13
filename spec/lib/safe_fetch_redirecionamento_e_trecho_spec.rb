require 'rails_helper'

# #1425 — duas opções do SafeFetch, desligadas por padrão (quem já usa não muda):
# `cross_origin_redirects: false` recusa o salto para outra origem ANTES de ir até ela, e
# `error_body_bytes:` guarda um pedaço curto do corpo de uma resposta de erro.
# rubocop:disable Style/RedundantFetchBlock
RSpec.describe SafeFetch do
  let(:url) { 'https://api.loja.test/dados' }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('api.loja.test').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('outro.test').and_return(['93.184.216.35'])
  end

  describe 'cross_origin_redirects: false' do
    it 'refuses a redirect to another host without requesting it' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://outro.test/x' })
      destino = stub_request(:get, 'https://outro.test/x')

      expect { described_class.fetch(url, cross_origin_redirects: false) { nil } }
        .to raise_error(SafeFetch::CrossOriginRedirectError, 'o endereço redireciona para outro domínio')
      expect(destino).not_to have_been_requested
    end

    it 'refuses a downgrade to http on the same host' do
      stub_request(:get, url).to_return(status: 301, headers: { 'Location' => 'http://api.loja.test/dados' })

      expect { described_class.fetch(url, cross_origin_redirects: false) { nil } }
        .to raise_error(SafeFetch::CrossOriginRedirectError)
    end

    it 'follows a relative redirect on the same host' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => '/dados/v2' })
      stub_request(:get, 'https://api.loja.test/dados/v2').to_return(status: 200, body: 'ok')

      lido = nil
      described_class.fetch(url, cross_origin_redirects: false, validate_content_type: false) { |r| lido = r.tempfile.read }

      expect(lido).to eq('ok')
    end

    it 'treats the same host in another letter case as the same origin' do
      allow(Resolv).to receive(:getaddresses).with('API.Loja.test').and_return(['93.184.216.34'])
      stub_request(:get, 'https://API.Loja.test/dados').to_return(status: 302, headers: { 'Location' => 'https://api.loja.test/v2' })
      stub_request(:get, 'https://api.loja.test/v2').to_return(status: 200, body: 'ok')

      lido = nil
      described_class.fetch('https://API.Loja.test/dados', cross_origin_redirects: false, validate_content_type: false) do |r|
        lido = r.tempfile.read
      end

      expect(lido).to eq('ok')
    end

    it 'keeps following cross-host redirects by default' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://outro.test/x' })
      stub_request(:get, 'https://outro.test/x').to_return(status: 200, body: 'ok')

      lido = nil
      described_class.fetch(url, validate_content_type: false) { |r| lido = r.tempfile.read }

      expect(lido).to eq('ok')
    end
  end

  describe 'error_body_bytes:' do
    it 'keeps at most that many bytes of an error body' do
      stub_request(:get, url).to_return(status: 404, body: "#{'a' * 100}#{'b' * 5000}")

      expect { described_class.fetch(url, error_body_bytes: 100) { nil } }
        .to raise_error(SafeFetch::HttpError) { |e| expect(e.body_excerpt).to eq('a' * 100) }
    end

    it 'keeps nothing by default' do
      stub_request(:get, url).to_return(status: 404, body: 'detalhe')

      expect { described_class.fetch(url) { nil } }
        .to raise_error(SafeFetch::HttpError) { |e| expect(e.body_excerpt).to be_nil }
    end
  end
end
# rubocop:enable Style/RedundantFetchBlock
