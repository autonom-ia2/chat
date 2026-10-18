require 'rails_helper'

# #1702 (prévia de link) — duas opções do SafeFetch, desligadas por padrão (quem já usa não muda):
# `allowed_ports:` confere a porta do endereço pedido e de CADA redirecionamento, e
# `truncate_at_max_bytes: true` corta o corpo no limite em vez de recusar a página inteira.
RSpec.describe SafeFetch do
  let(:url) { 'https://site.loja.test/pagina' }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('site.loja.test').and_return(['93.184.216.34'])
    allow(Resolv).to receive(:getaddresses).with('outro.test').and_return(['93.184.216.35'])
  end

  describe 'allowed_ports:' do
    it 'refuses a redirect to a port outside the list without requesting it' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://outro.test:8443/x' })
      destino = stub_request(:get, 'https://outro.test:8443/x')

      expect { described_class.fetch(url, allowed_ports: [80, 443]) { nil } }
        .to raise_error(SafeFetch::UnsafeUrlError, 'redirect to a port that is not allowed')
      expect(destino).not_to have_been_requested
    end

    it 'refuses a scheme-relative redirect to a port outside the list' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => '//outro.test:8080/x' })
      destino = stub_request(:get, 'https://outro.test:8080/x')

      expect { described_class.fetch(url, allowed_ports: [80, 443]) { nil } }
        .to raise_error(SafeFetch::UnsafeUrlError, 'redirect to a port that is not allowed')
      expect(destino).not_to have_been_requested
    end

    it 'refuses a starting address on a port outside the list' do
      destino = stub_request(:get, 'https://site.loja.test:8080/pagina')

      expect { described_class.fetch('https://site.loja.test:8080/pagina', allowed_ports: [80, 443]) { nil } }
        .to raise_error(SafeFetch::UnsafeUrlError, 'port 8080 not allowed')
      expect(destino).not_to have_been_requested
    end

    # Antes e depois do #1702 o salto sem barra é recusado (o ssrf_filter não o monta); só a classe do erro mudou.
    it 'keeps refusing a relative redirect without leading slash, without requesting it' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'outra' })
      destino = stub_request(:get, 'https://site.loja.test/outra')

      expect { described_class.fetch(url, cross_origin_redirects: false) { nil } }
        .to raise_error(SafeFetch::CrossOriginRedirectError)
      expect(destino).not_to have_been_requested
    end

    it 'follows a redirect to an allowed port and a relative redirect' do
      stub_request(:get, url).to_return(status: 301, headers: { 'Location' => 'http://outro.test/x' })
      stub_request(:get, 'http://outro.test/x').to_return(status: 302, headers: { 'Location' => '/y' })
      stub_request(:get, 'http://outro.test/y').to_return(status: 200, body: 'ok')

      lido = nil
      described_class.fetch(url, allowed_ports: [80, 443], validate_content_type: false) { |r| lido = r.tempfile.read }

      expect(lido).to eq('ok')
    end

    it 'keeps following any port by default' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://outro.test:8443/x' })
      stub_request(:get, 'https://outro.test:8443/x').to_return(status: 200, body: 'ok')

      lido = nil
      described_class.fetch(url, validate_content_type: false) { |r| lido = r.tempfile.read }

      expect(lido).to eq('ok')
    end
  end

  describe 'cross_origin_redirects: false' do
    it 'refuses a scheme-relative redirect to another host' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => '//outro.test/x' })
      destino = stub_request(:get, 'https://outro.test/x')

      expect { described_class.fetch(url, cross_origin_redirects: false) { nil } }
        .to raise_error(SafeFetch::CrossOriginRedirectError)
      expect(destino).not_to have_been_requested
    end
  end

  describe 'truncate_at_max_bytes: true' do
    let(:pagina) { "<html><head><title>Loja</title></head><body>#{'x' * 5000}</body></html>" }

    it 'returns only the first max_bytes of a larger body' do
      stub_request(:get, url).to_return(status: 200, body: pagina, headers: { 'Content-Type' => 'text/html' })

      lido = nil
      tipo = nil
      described_class.fetch(url, max_bytes: 100, truncate_at_max_bytes: true, allowed_content_types: ['text/html']) do |r|
        lido = r.tempfile.read
        tipo = r.content_type
      end

      expect(lido).to eq(pagina.byteslice(0, 100))
      expect(tipo).to eq('text/html')
    end

    it 'does not refuse an announced Content-Length above the limit' do
      stub_request(:get, url).to_return(status: 200, body: pagina,
                                        headers: { 'Content-Type' => 'text/html', 'Content-Length' => pagina.bytesize.to_s })

      lido = nil
      described_class.fetch(url, max_bytes: 100, truncate_at_max_bytes: true, allowed_content_types: ['text/html']) do |r|
        lido = r.tempfile.read
      end

      expect(lido.bytesize).to eq(100)
    end

    it 'keeps refusing a larger body by default' do
      stub_request(:get, url).to_return(status: 200, body: pagina, headers: { 'Content-Type' => 'text/html' })

      expect { described_class.fetch(url, max_bytes: 100, allowed_content_types: ['text/html']) { nil } }
        .to raise_error(SafeFetch::FileTooLargeError)
    end
  end
end
