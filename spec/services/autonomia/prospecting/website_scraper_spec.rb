require 'rails_helper'

# Caracterização do raspador de site (#683) e guarda de destino (#476). O DNS é dublado e o HTTP passa
# pelo WebMock, menos no bloco "conexão real", que usa um servidor em 127.0.0.1.
RSpec.describe Autonomia::Prospecting::WebsiteScraper do
  let(:public_ip) { '93.184.216.34' }
  let(:html) do
    <<~HTML
      <html>
        <head>
          <title>Titulo da aba</title>
          <meta property="og:title" content="Clinica Sorriso">
          <meta name="description" content="Odontologia em Curitiba">
          <script>var fone = '(41) 91111-1111';</script>
        </head>
        <body>
          <p>Ligue (41) 3333-4444. CNPJ 12.345.678/0001-90</p>
          <a href="mailto:contato@sorriso.example.com?subject=Oi">E-mail</a>
          <a href="https://wa.me/5541999990000">WhatsApp</a>
          <a href="https://www.facebook.com/sharer/sharer.php?u=x">Compartilhar</a>
          <a href="https://www.facebook.com/clinicasorriso">Facebook</a>
          <a href="https://www.instagram.com/clinicasorriso">Instagram</a>
          <a href="https://www.linkedin.com/feed/">Feed</a>
          <a href="https://www.linkedin.com/company/clinicasorriso">LinkedIn</a>
          <a href="/contato">Contato</a>
        </body>
      </html>
    HTML
  end

  before { allow(Resolv).to receive(:getaddresses).and_return([public_ip]) }

  def scrape(url)
    described_class.new(url: url).perform.data
  end

  it 'extrai título, descrição, contatos, redes e CNPJ da página' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 200, body: html)

    data = scrape('https://sorriso.example.com/')

    expect(data).to include(
      'website' => 'https://sorriso.example.com/',
      'title' => 'Clinica Sorriso',
      'description' => 'Odontologia em Curitiba',
      'email' => 'contato@sorriso.example.com',
      'phone' => '+554133334444',
      'whatsapp' => '+5541999990000',
      'instagram' => 'https://www.instagram.com/clinicasorriso',
      'facebook' => 'https://www.facebook.com/clinicasorriso',
      'linkedin' => 'https://www.linkedin.com/company/clinicasorriso',
      'cnpj' => '12.345.678/0001-90'
    )
    expect(data['source_urls']).to include('https://sorriso.example.com/contato')
    expect(data['text_excerpt']).not_to include('var fone')
    expect(data).not_to have_key('error')
  end

  it 'completa https:// quando o endereço vem sem esquema' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 200, body: '<title>Sorriso</title>')

    expect(scrape('sorriso.example.com/')).to include('website' => 'https://sorriso.example.com/', 'title' => 'Sorriso')
  end

  it 'usa o e-mail do texto e o telefone como WhatsApp quando a página só cita whatsapp' do
    body = '<p>Fale no WhatsApp (41) 98888-7777 ou escreva para vendas@sorriso.example.com</p>'
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 200, body: body)

    data = scrape('https://sorriso.example.com/')

    expect(data['email']).to eq('vendas@sorriso.example.com')
    expect(data['whatsapp']).to eq('+5541988887777')
  end

  it 'devolve erro missing_website com endereço vazio, sem chamar a rede' do
    expect(scrape('  ')).to include('error' => 'missing_website')
  end

  it 'devolve erro http_<código> quando o site responde com falha' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 404, body: 'nada')

    expect(scrape('https://sorriso.example.com/')).to include('error' => 'http_404')
  end

  it 'manda User-Agent de navegador' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 200, body: '<title>Sorriso</title>')

    scrape('https://sorriso.example.com/')

    expect(WebMock).to have_requested(:get, 'https://sorriso.example.com/')
      .with(headers: { 'User-Agent' => described_class::USER_AGENT })
    expect(described_class::USER_AGENT).to start_with('Mozilla/5.0')
  end

  it 'devolve empty_page quando o site responde sem conteúdo' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 200, body: '<html><body> </body></html>')

    expect(scrape('https://sorriso.example.com/')).to include('error' => 'empty_page')
  end

  it 'recusa conteúdo que não é página (PDF, imagem)' do
    stub_request(:get, 'https://sorriso.example.com/')
      .to_return(status: 200, body: '%PDF-1.4', headers: { 'Content-Type' => 'application/pdf' })

    expect(scrape('https://sorriso.example.com/')).to include('error' => 'unsupported_content_type')
  end

  it 'devolve timeout quando o site não responde a tempo' do
    stub_request(:get, 'https://sumiu.example.com/').to_timeout

    expect(scrape('https://sumiu.example.com/')).to include('error' => 'timeout')
  end

  describe 'guarda de destino (#476)' do
    it 'bloqueia localhost e endereço de rede interna' do
      allow(Resolv).to receive(:getaddresses).with('interno.example.com').and_return(['10.0.0.5'])

      expect(scrape('http://localhost:3000')).to include('error' => 'blocked_url', 'message' => 'blocked_host')
      expect(scrape('https://interno.example.com')).to include('error' => 'blocked_url', 'message' => 'blocked_host')
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'bloqueia a faixa CGNAT 100.64.0.0/10' do
      allow(Resolv).to receive(:getaddresses).with('cgnat.example.com').and_return(['100.64.0.1'])

      expect(scrape('https://cgnat.example.com/')).to include('error' => 'blocked_url')
    end

    it 'bloqueia IPv4 mapeado em IPv6 (::ffff:169.254.169.254), escrito na URL ou vindo do DNS' do
      allow(Resolv).to receive(:getaddresses).with('mapeado.example.com').and_return(['::ffff:169.254.169.254'])

      expect(scrape('http://[::ffff:169.254.169.254]/latest/meta-data/')).to include('error' => 'blocked_url')
      expect(scrape('https://mapeado.example.com/')).to include('error' => 'blocked_url')
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'bloqueia URL com usuário embutido' do
      expect(scrape('http://user@sorriso.example.com/')).to include('error' => 'blocked_url', 'message' => 'invalid_url')
      expect(scrape('https://user:senha@sorriso.example.com/')).to include('error' => 'blocked_url', 'message' => 'invalid_url')
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'bloqueia host que não resolve no DNS, sem tentar conectar' do
      allow(Resolv).to receive(:getaddresses).and_return([])

      expect(scrape('https://sumiu.example.com/')).to include('error' => 'blocked_url')
      expect(WebMock).not_to have_requested(:any, /.*/)
    end

    it 'bloqueia DNS que responde público na validação e interno na conexão' do
      allow(Resolv).to receive(:getaddresses).with('troca.example.com').and_return([public_ip], ['169.254.169.254'])
      stub_request(:get, 'https://troca.example.com/').to_return(status: 200, body: '<title>Nao devia</title>')

      expect(scrape('https://troca.example.com/')).to include('error' => 'blocked_url', 'message' => 'blocked_host')
      expect(WebMock).not_to have_requested(:get, 'https://troca.example.com/')
    end

    it 'bloqueia redirecionamento para rede interna' do
      allow(Resolv).to receive(:getaddresses).with('interno.example.com').and_return(['192.168.0.10'])
      stub_request(:get, 'https://sorriso.example.com/')
        .to_return(status: 302, headers: { 'Location' => 'https://interno.example.com/admin' })

      expect(scrape('https://sorriso.example.com/')).to include('error' => 'blocked_url', 'message' => 'blocked_host')
      expect(WebMock).not_to have_requested(:get, 'https://interno.example.com/admin')
    end

    it 'bloqueia redirecionamento para IP interno escrito na URL e para URL com usuário' do
      stub_request(:get, 'https://sorriso.example.com/')
        .to_return(status: 302, headers: { 'Location' => 'http://169.254.169.254/latest/meta-data/' })
      expect(scrape('https://sorriso.example.com/')).to include('error' => 'blocked_url')

      stub_request(:get, 'https://sorriso.example.com/')
        .to_return(status: 302, headers: { 'Location' => 'https://user@outro.example.com/' })
      expect(scrape('https://sorriso.example.com/')).to include('error' => 'blocked_url', 'message' => 'invalid_url')
    end

    it 'segue até dois redirecionamentos e desiste no terceiro' do
      stub_request(:get, 'https://a.example.com/').to_return(status: 301, headers: { 'Location' => 'https://b.example.com/' })
      stub_request(:get, 'https://b.example.com/').to_return(status: 301, headers: { 'Location' => '/c' })
      stub_request(:get, 'https://b.example.com/c').to_return(status: 200, body: '<title>Final</title>')

      expect(scrape('https://a.example.com/')).to include('title' => 'Final')

      stub_request(:get, 'https://b.example.com/c').to_return(status: 301, headers: { 'Location' => 'https://d.example.com/' })

      expect(scrape('https://a.example.com/')).to include('error' => 'too_many_redirects')
    end

    it 'chama de invalid_redirect um redirecionamento sem Location' do
      stub_request(:get, 'https://sorriso.example.com/').to_return(status: 302)

      expect(scrape('https://sorriso.example.com/')).to include('error' => 'invalid_redirect')
    end
  end

  describe 'conexão real, sem WebMock' do
    let(:resolver_local) { ->(_host) { ['127.0.0.1'] } }

    # O servidor local está em 127.0.0.1, que a guarda recusa; aqui ela é liberada para medir a conexão.
    before do
      guarda = instance_double(Autonomia::Agents::Knowledge::UrlGuard, validate!: true)
      allow(Autonomia::Agents::Knowledge::UrlGuard).to receive(:new).and_return(guarda)
      allow(Autonomia::Agents::Knowledge::UrlGuard).to receive(:blocked_ip?).and_return(false)
    end

    it 'conecta no IP fixado mesmo com um nome que o DNS não conhece' do
      servidor = servidor_http_local do |srv, cliente|
        corpo = '<title>Fixado</title>'
        srv.escrever(cliente, srv.cabecalhos('200 OK', 'text/html; charset=utf-8', corpo.bytesize) + corpo)
      end
      porta = URI(servidor.url('/')).port

      data = sem_webmock { described_class.new(url: "http://fixado.invalid:#{porta}/", resolver: resolver_local).perform.data }
      servidor.parar

      expect(data).to include('title' => 'Fixado')
    end

    it 'para de ler no limite de tamanho e analisa só o que leu' do
      total = 4 * described_class::MAX_BODY_BYTES
      servidor = servidor_http_local do |srv, cliente|
        next unless srv.escrever(cliente, "#{srv.cabecalhos('200 OK', 'text/html', total)}<title>Grande</title>")

        pedaco = 'a' * 16.kilobytes
        (total / pedaco.bytesize).times { break unless srv.escrever(cliente, pedaco) }
      end
      porta = URI(servidor.url('/')).port

      data = sem_webmock { described_class.new(url: "http://grande.invalid:#{porta}/", resolver: resolver_local).perform.data }
      servidor.parar

      expect(data).to include('title' => 'Grande', 'truncated' => true)
      expect(data).not_to have_key('error')
      expect(servidor.bytes_escritos).to be < total
    end
  end
end
