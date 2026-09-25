require 'rails_helper'

# Transporte dos cadastros públicos: hosts fixos, User-Agent próprio, sem seguir redirecionamento e corpo até 1 MB.
RSpec.describe Autonomia::Prospecting::Research::Registry::HttpTransport do
  let(:url) { 'https://api.opencnpj.org/11222333000181' }

  def request(target = url)
    described_class.new.request(url: target, timeout: 5)
  end

  it 'manda o User-Agent autonomia-radar/1.0 e pede JSON' do
    stub_request(:get, url).to_return(status: 200, body: '{"cnpj":"11222333000181"}')

    response = request

    expect(response.status).to eq(200)
    expect(response.body).to eq('cnpj' => '11222333000181')
    expect(WebMock).to have_requested(:get, url).with(headers: { 'User-Agent' => 'autonomia-radar/1.0', 'Accept' => 'application/json' })
  end

  it 'recusa redirecionamento: devolve o 3xx sem ler o corpo e sem seguir' do
    stub_request(:get, url).to_return(status: 302, headers: { 'Location' => 'https://evil.example/' }, body: '{"x":1}')

    response = request

    expect(response.status).to eq(302)
    expect(response.body).to be_nil
    expect(WebMock).not_to have_requested(:get, 'https://evil.example/')
  end

  it 'recusa corpo acima de 1 MB' do
    stub_request(:get, url).to_return(status: 200, body: "{\"x\":\"#{'a' * 1.megabyte}\"}")

    expect { request }.to raise_error(described_class::BodyTooLarge)
  end

  it 'recusa quando o Content-Length já anuncia mais de 1 MB' do
    stub_request(:get, url).to_return(status: 200, body: '{}', headers: { 'Content-Length' => (1.megabyte + 1).to_s })

    expect { request }.to raise_error(described_class::BodyTooLarge)
  end

  it 'entrega corpo nil quando a resposta não é JSON' do
    stub_request(:get, url).to_return(status: 200, body: '<html>fora do ar</html>')

    expect(request.body).to be_nil
  end

  it 'guarda só o Retry-After dos cabeçalhos' do
    stub_request(:get, url).to_return(status: 429, headers: { 'Retry-After' => '1', 'Set-Cookie' => 'a=b' })

    expect(request.headers).to eq('retry-after' => '1')
  end

  it 'só fala com os quatro hosts fixos, em https' do
    expect { request('https://evil.example/11222333000181') }.to raise_error(described_class::HostNotAllowed)
    expect { request('http://api.opencnpj.org/11222333000181') }.to raise_error(described_class::HostNotAllowed)
    expect(described_class::ALLOWED_HOSTS).to match_array(%w[api.opencnpj.org brasilapi.com.br publica.cnpj.ws open.cnpja.com])
  end
end
