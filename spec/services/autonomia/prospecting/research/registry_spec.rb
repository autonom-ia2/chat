require 'rails_helper'

# Registry.fetch de ponta a ponta pelo transporte HTTP real, com WebMock no lugar dos cadastros.
RSpec.describe Autonomia::Prospecting::Research::Registry do
  let(:cnpj) { '11222333000181' }
  let(:open_url) { "https://api.opencnpj.org/#{cnpj}" }
  let(:brasil_url) { "https://brasilapi.com.br/api/cnpj/v1/#{cnpj}" }

  def fixture(name)
    Rails.root.join('spec/fixtures/prospecting/registry', "#{name}.json").read
  end

  it 'devolve a empresa da primeira fonte que responde' do
    stub_request(:get, open_url).to_return(status: 200, body: fixture('opencnpj-contrato-real'))

    company = described_class.fetch('11.222.333/0001-81')

    expect(company).not_to be_failed
    expect(company).to have_attributes(cnpj: cnpj, legal_name: 'EMPRESA ALFA SINTETICA LTDA', provider: 'OpenCNPJ')
    expect(company.qsa.map(&:name)).to eq(['PESSOA FISICA SINTETICA', 'PESSOA JURIDICA SINTETICA'])
  end

  it 'cai para a próxima fonte quando a primeira está fora do ar' do
    stub_request(:get, open_url).to_raise(Errno::ECONNREFUSED)
    stub_request(:get, brasil_url).to_return(status: 200, body: fixture('brasilapi-success'))

    company = described_class.fetch(cnpj)

    expect(company.provider).to eq('BrasilAPI')
    expect(WebMock).to have_requested(:get, brasil_url).once
  end

  it 'cai para a próxima fonte quando a primeira redireciona ou manda corpo grande demais' do
    stub_request(:get, open_url).to_return(status: 301, headers: { 'Location' => 'https://evil.example/' })
    stub_request(:get, brasil_url).to_return(status: 200, body: "{\"x\":\"#{'a' * 1.megabyte}\"}")
    stub_request(:get, "https://publica.cnpj.ws/cnpj/#{cnpj}").to_return(status: 200, body: fixture('cnpjws-success'))

    expect(described_class.fetch(cnpj).provider).to eq('CNPJ.ws')
  end

  it 'devolve falha tipada, sem dado do cadastro, quando todas as fontes falham' do
    described_class::PROVIDERS.each { |provider| stub_request(:get, provider.url(cnpj)).to_return(status: 404) }

    failure = described_class.fetch(cnpj)

    expect(failure).to be_failed
    expect(failure).to have_attributes(cnpj: cnpj, reason: :providers_exhausted)
    expect(failure.attempts.pluck('provider')).to eq(%w[OpenCNPJ BrasilAPI CNPJ.ws CNPJá])
  end

  it 'devolve falha invalid_cnpj sem chamar a rede' do
    stubs = described_class::PROVIDERS.map { |provider| stub_request(:get, provider.url('12300000000000')) }

    expect(described_class.fetch('123')).to have_attributes(reason: :invalid_cnpj, attempts: [])
    stubs.each { |stub| expect(stub).not_to have_been_requested }
  end
end
