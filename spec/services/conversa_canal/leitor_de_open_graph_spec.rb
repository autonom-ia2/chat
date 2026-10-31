require 'rails_helper'

# #1702 — prévia de link: leitura do Open Graph pelo servidor, sempre pelo SafeFetch.
describe ConversaCanal::LeitorDeOpenGraph do
  let(:url) { 'https://exemplo.com.br/seguro' }
  let(:html_com_og) { Rails.root.join('spec/fixtures/files/conversa_canal/pagina_com_open_graph.html').read }
  let(:html_sem_og) { Rails.root.join('spec/fixtures/files/conversa_canal/pagina_sem_open_graph.html').read }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('exemplo.com.br').and_return(['93.184.216.34'])
  end

  def servir(body, tipo: 'text/html; charset=utf-8', status: 200)
    stub_request(:get, url).to_return(status: status, body: body, headers: { 'Content-Type' => tipo })
  end

  it 'lê og:title, og:description, og:site_name e a og:image relativa montada sobre o endereço' do
    servir(html_com_og)

    expect(described_class.ler(url)).to eq(
      'url' => url,
      'final_url' => url,
      'title' => 'Seguro auto em 5 minutos',
      'description' => 'Cotação online, sem ligação.',
      'site_name' => 'Exemplo Seguros',
      'image_source' => 'https://exemplo.com.br/imagens/capa.png'
    )
  end

  it 'usa o <title> e a meta description quando a página não tem Open Graph' do
    servir(html_sem_og)

    expect(described_class.ler(url)).to eq('url' => url, 'final_url' => url, 'title' => 'Só o título', 'description' => 'Descrição comum')
  end

  # #1775: o redirecionador (encurtador, redirect aberto no site de outra empresa) não empresta o domínio ao texto lido.
  it 'grava o endereço final, depois do redirecionamento' do
    destino = 'https://destino.exemplo.net/oferta'
    allow(Resolv).to receive(:getaddresses).with('destino.exemplo.net').and_return(['93.184.216.35'])
    stub_request(:get, url).to_return(status: 302, headers: { 'Location' => destino })
    stub_request(:get, destino).to_return(status: 200, body: html_sem_og, headers: { 'Content-Type' => 'text/html' })

    expect(described_class.ler(url)).to include('url' => url, 'final_url' => destino)
  end

  it 'aceita resposta parcial (206) do pedido com Range' do
    servir(html_com_og, status: 206)

    expect(described_class.ler(url)['title']).to eq('Seguro auto em 5 minutos')
  end

  it 'pede só o começo da página, com user-agent próprio e sem cookie' do
    servir(html_com_og)

    described_class.ler(url)

    expect(
      a_request(:get, url).with do |pedido|
        pedido.headers['Range'] == 'bytes=0-524287' && pedido.headers['User-Agent'] == described_class::USER_AGENT &&
          pedido.headers['Cookie'].nil?
      end
    ).to have_been_made.once
  end

  it 'devolve nil para página sem título' do
    servir('<html><head></head><body>nada</body></html>')

    expect(described_class.ler(url)).to be_nil
  end

  it 'recusa o que não é HTML' do
    servir('{}', tipo: 'application/json')

    expect { described_class.ler(url) }.to raise_error(SafeFetch::UnsupportedContentTypeError)
  end

  it 'lê só os primeiros 512 KB quando o servidor ignora o Range (o <head> vem antes)' do
    servir("<html><head><title>Loja grande</title></head><body>#{'a' * 600.kilobytes}</body></html>")

    expect(described_class.ler(url)).to eq('url' => url, 'final_url' => url, 'title' => 'Loja grande')
  end

  it 'não pede nada a porta fora de 80/443 nem a esquema que não é web' do
    expect(described_class.ler('https://exemplo.com.br:8443/x')).to be_nil
    expect(described_class.ler('ftp://exemplo.com.br/x')).to be_nil
    expect(a_request(:get, 'https://exemplo.com.br:8443/x')).not_to have_been_made
  end

  context 'with endereço da rede interna (SSRF)' do
    it 'recusa loopback' do
      expect { described_class.ler('http://127.0.0.1/admin') }.to raise_error(SafeFetch::UnsafeUrlError)
    end

    it 'recusa o metadata da nuvem (169.254.169.254)' do
      expect { described_class.ler('http://169.254.169.254/latest/meta-data/') }.to raise_error(SafeFetch::UnsafeUrlError)
    end

    it 'recusa nome que resolve para IP privado' do
      allow(Resolv).to receive(:getaddresses).with('interno.exemplo.com.br').and_return(['10.0.0.5'])

      expect { described_class.ler('https://interno.exemplo.com.br/') }.to raise_error(SafeFetch::UnsafeUrlError)
    end

    it 'recusa redirecionamento para IP privado' do
      stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'http://192.168.0.10/painel' })

      expect { described_class.ler(url) }.to raise_error(SafeFetch::UnsafeUrlError)
      expect(a_request(:get, 'http://192.168.0.10/painel')).not_to have_been_made
    end

    it 'para depois de 3 redirecionamentos' do
      4.times do |i|
        stub_request(:get, "https://exemplo.com.br/r#{i}")
          .to_return(status: 302, headers: { 'Location' => "https://exemplo.com.br/r#{i + 1}" })
      end

      expect { described_class.ler('https://exemplo.com.br/r0') }.to raise_error(SafeFetch::UnsafeUrlError)
    end
  end
end
