require 'rails_helper'

# Caracterização do raspador de site antes da E0 (#683). Nenhuma chamada de
# rede real: o DNS é dublado e o HTTP passa pelo WebMock.
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

  it 'bloqueia localhost e endereço de rede interna' do
    allow(Resolv).to receive(:getaddresses).with('interno.example.com').and_return(['10.0.0.5'])

    expect(scrape('http://localhost:3000')).to include('error' => 'argument_error', 'message' => 'blocked_host')
    expect(scrape('https://interno.example.com')).to include('error' => 'argument_error', 'message' => 'blocked_host')
  end

  it 'bloqueia redirecionamento para rede interna' do
    allow(Resolv).to receive(:getaddresses).with('interno.example.com').and_return(['192.168.0.10'])
    stub_request(:get, 'https://sorriso.example.com/')
      .to_return(status: 302, headers: { 'Location' => 'https://interno.example.com/admin' })

    expect(scrape('https://sorriso.example.com/')).to include('error' => 'argument_error', 'message' => 'blocked_host')
  end

  it 'segue até dois redirecionamentos e desiste no terceiro' do
    stub_request(:get, 'https://a.example.com/').to_return(status: 301, headers: { 'Location' => 'https://b.example.com/' })
    stub_request(:get, 'https://b.example.com/').to_return(status: 301, headers: { 'Location' => 'https://c.example.com/' })
    stub_request(:get, 'https://c.example.com/').to_return(status: 200, body: '<title>Final</title>')

    expect(scrape('https://a.example.com/')).to include('title' => 'Final')

    stub_request(:get, 'https://c.example.com/').to_return(status: 301, headers: { 'Location' => 'https://d.example.com/' })

    expect(scrape('https://a.example.com/')).to include('error' => 'argument_error', 'message' => 'too_many_redirects')
  end

  it 'chama de too_many_redirects um redirecionamento sem Location' do
    stub_request(:get, 'https://sorriso.example.com/').to_return(status: 302)

    expect(scrape('https://sorriso.example.com/')).to include('message' => 'too_many_redirects')
  end

  it 'aceita host que não resolve no DNS e devolve o erro da conexão' do
    allow(Resolv).to receive(:getaddresses).and_return([])
    stub_request(:get, 'https://sumiu.example.com/').to_timeout

    expect(scrape('https://sumiu.example.com/')).to include('error' => 'open_timeout')
  end
end
