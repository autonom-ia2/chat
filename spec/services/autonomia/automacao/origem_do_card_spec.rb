require 'rails_helper'

# G29 (#2702): a origem do card vira uma escolha fechada da receita. O `crm_cards.source` vem de cada lugar que cria
# card; o que não tem grupo cai em "outro" e o filtro "veio de um formulário de anúncio" nunca casaria.
RSpec.describe Autonomia::Automacao::OrigemDoCard do
  it 'põe cada source conhecido no grupo dele', :aggregate_failures do
    expect(described_class.de(Crm::MetaAds::LeadForms::Importer::SOURCE)).to eq('formulario_de_anuncio')
    expect(described_class.de('Channel::Whatsapp')).to eq('conversa')
    expect(described_class.de('Channel::Instagram')).to eq('conversa')
    expect(described_class.de('autonomia_prospecting')).to eq('prospeccao')
    agenda = [*Crm::BookingV2::Results::BOOKING_SOURCES, Crm::BookingV2::ContactRequest::SOURCE, 'public_booking']
    expect(agenda.map { |source| described_class.de(source) }.uniq).to eq(['agenda'])
    expect([nil, '', 'outra_coisa'].map { |source| described_class.de(source) }.uniq).to eq(['outro'])
  end

  it 'tem como opções exatamente os grupos' do
    expect(Autonomia::Automacao::Valores::FECHADOS.dig('card.origem', 'opcoes')).to eq(described_class::GRUPOS)
  end

  # Quem cria card novo grava um `source`. Lugar novo que cria card entra nesta lista depois de dizer, em OrigemDoCard,
  # de que grupo é o source dele; sem isso, o card dele cai em "outro" sem ninguém ver.
  it 'conhece todo lugar do código que cria card' do
    criam = Rails.root.glob('{app,enterprise,lib}/**/*.rb').select { |arquivo| arquivo.read.include?('Cards::Creator.new(') }
    relativos = criam.map { |arquivo| arquivo.relative_path_from(Rails.root).to_s }

    expect(relativos).to match_array(described_class::QUEM_CRIA_CARD),
                         'lugar novo cria card: diga em OrigemDoCard de que grupo é o source dele e ponha o arquivo em QUEM_CRIA_CARD'
  end
end
