require 'rails_helper'

# #723: dado de fora maior que a coluna string (255) não derruba mais a busca nem o enriquecimento.
RSpec.describe Autonomia::Prospecting::ColumnFit do
  let(:long) { 'x' * 300 }

  describe '.url' do
    it 'devolve como veio o que já cabe, sem reescrever encoding' do
      url = 'https://a.com/p?q=a+b&r=c%20d&s'
      expect(described_class.url(url)).to eq(url)
    end

    it 'tira só o rastreio e mantém o resto da query' do
      expect(described_class.url("https://maps.google.com/?cid=9&utm_source=#{long}", drop_query: false))
        .to eq('https://maps.google.com/?cid=9')
    end

    it 'no link que depende da query, prefere vazio a um link genérico' do
      expect(described_class.url("https://maps.google.com/?cid=9&g_mp=#{long}", drop_query: false)).to be_nil
    end

    it 'no site, tira a query quando só o rastreio não basta' do
      expect(described_class.url("https://site.com/pagina?sessao=#{long}")).to eq('https://site.com/pagina')
    end

    it 'fica vazio quando nem sem query cabe' do
      expect(described_class.url("https://site.com/#{long}")).to be_nil
    end
  end

  describe '.text' do
    it 'corta no limite e deixa nil como nil' do
      expect(described_class.text(long).length).to eq(255)
      expect(described_class.text(nil)).to be_nil
      expect(described_class.text('Padaria')).to eq('Padaria')
    end
  end

  it 'link de rede longo raspado do site não quebra o enriquecimento do lead' do
    lead = Autonomia::Prospecting::Lead.new(enriched_data: {})
    merge = Autonomia::Prospecting::EnrichmentMerge.new(
      lead: lead, scraped: { 'facebook' => "https://facebook.com/pagina?fbclid=#{long}", 'email' => 'a@b.com' }, ai_data: {}
    )

    expect(merge.attributes).to include(enriched_facebook: 'https://facebook.com/pagina', enriched_email: 'a@b.com')
  end
end
