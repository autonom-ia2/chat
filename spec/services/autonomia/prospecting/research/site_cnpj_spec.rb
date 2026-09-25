require 'rails_helper'

# CNPJ do site lido pela própria pesquisa (#679), como o collectSiteSignal do Orth. O DNS é dublado e a página vem do
# WebMock. A coluna enriched_cnpj nunca é fonte: é o que impede o CNPJ aceito numa pesquisa de corroborar a seguinte.
RSpec.describe Autonomia::Prospecting::Research::SiteCnpj do
  let(:site_url) { 'https://www.alfa-sintetica.com.br/' }
  let(:account) { create(:account) }

  def create_lead(**attributes)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'google_places', provider_place_id: 'places/alfa',
                                         name: 'Alfa Sintetica', **attributes)
  end

  before { allow(Resolv).to receive(:getaddresses).and_return(['93.184.216.34']) }

  it 'lê o CNPJ que a página mostra, sem depender do enriquecimento' do
    stub_request(:get, site_url).to_return(status: 200, body: '<html><body><p>CNPJ 11.222.333/0001-81</p></body></html>')

    expect(described_class.read(create_lead(website: site_url))).to eq('11.222.333/0001-81')
  end

  it 'página sem CNPJ devolve nil, mesmo com enriched_cnpj preenchido' do
    stub_request(:get, site_url).to_return(status: 200, body: '<html><body><p>Alfa Sintetica</p></body></html>')

    expect(described_class.read(create_lead(website: site_url, enriched_cnpj: '11.222.333/0001-81'))).to be_nil
  end

  it 'página fora do ar usa o CNPJ que o raspador guardou do site, nunca enriched_cnpj' do
    stub_request(:get, site_url).to_return(status: 503)
    lead = create_lead(website: site_url, enriched_cnpj: '99.888.777/0001-66', enriched_data: { 'cnpj' => '11.222.333/0001-81' })

    expect(described_class.read(lead)).to eq('11.222.333/0001-81')
  end

  it 'página fora do ar e nada raspado antes devolve nil' do
    stub_request(:get, site_url).to_return(status: 503)

    expect(described_class.read(create_lead(website: site_url, enriched_cnpj: '11.222.333/0001-81'))).to be_nil
  end

  it 'lead sem site devolve nil sem nenhuma requisição' do
    expect(described_class.read(create_lead(enriched_cnpj: '11.222.333/0001-81'))).to be_nil
    expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
  end
end
