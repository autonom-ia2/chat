require 'rails_helper'

# Os campos dentro de um texto (#1099, entrega C), lidos como a checagem de qualidade lê, para trocar só o campo pedido.
RSpec.describe EmailCampaigns::Import::TagText do
  it 'lists the keys the way the quality check reads them' do
    expect(described_class.keys('Oi {{ nome }}, {{-cupom}} e {{ email }} {{ sem fim')).to eq(%w[nome cupom email])
  end

  it 'swaps only the tags of the asked key, whatever their spacing' do
    source = 'Oi {{ nome }}! Cupom: {{cupom}} e {{ cupom }}. {{ incompleto'

    expect(described_class.replace(source, 'cupom', 'OUTUBRO10')).to eq('Oi {{ nome }}! Cupom: OUTUBRO10 e OUTUBRO10. {{ incompleto')
    expect(described_class.replace(source, 'outro', 'x')).to eq(source)
  end
end
