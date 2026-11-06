require 'rails_helper'

# O tipo do campo de destino de um valor calculado (G16 do #2414), pelo formato da ação no Guia.
RSpec.describe Autonomia::Automacao::CampoDaAcao do
  let(:card) { described_class.new('PATCH crm/cards/:id') }

  it 'campo inteiro aceita o número e o texto dele em base 10, e só', :aggregate_failures do
    expect([3, '3', ' 12 '].map { |valor| card.cabe?(%w[card score], valor) }).to all(be(true))
    expect(['3.5', '0x1A', 'três', nil, 2.5].map { |valor| card.cabe?(%w[card score], valor) }).to all(be(false))
  end

  it 'campo de data aceita "AAAA-MM-DD", com ou sem a hora, e recusa texto', :aggregate_failures do
    expect(card.cabe?(%w[card expected_close_at], '2027-05-04')).to be(true)
    expect(card.cabe?(%w[card expected_close_at], '2027-05-04T10:00:00Z')).to be(true)
    expect(card.cabe?(%w[card expected_close_at], 'Revisão')).to be(false)
  end

  it 'dentro de um campo JSON qualquer valor cabe, como na tela' do
    expect(card.cabe?(%w[card custom_attributes revisao], 'qualquer coisa')).to be(true)
  end
end
