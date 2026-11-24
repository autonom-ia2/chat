require 'rails_helper'

# #3082 (PR B) — o que as IAs recebem dos campos personalizados.
RSpec.describe Relationships::CamposParaIa do
  let(:account) { create(:account) }
  let(:leitor) { described_class.new(account.reload) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'placa',
                                         attribute_display_name: 'Placa do carro', attribute_description: '  A placa do carro segurado. ')
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'renovacao',
                                         attribute_display_name: 'Renovação').destroy!
  end

  it 'tira dos valores só o campo apagado; a chave que nunca foi campo continua' do
    valores = leitor.valores({ 'placa' => 'ABC1D23', 'renovacao' => '2026-12-01', 'melhor_horario' => 'manhã' }, 'contact_attribute')

    expect(valores).to eq('placa' => 'ABC1D23', 'melhor_horario' => 'manhã')
  end

  it 'dá o nome e o "Para que serve" só das chaves com definição' do
    expect(leitor.significados(%w[placa melhor_horario], 'contact_attribute'))
      .to eq('placa' => { name: 'Placa do carro', purpose: 'A placa do carro segurado.' })
  end

  it 'não mistura pessoa e empresa' do
    expect(leitor.significados(%w[placa], 'company_attribute')).to eq({})
    expect(leitor.valores({ 'renovacao' => 'x' }, 'company_attribute')).to eq('renovacao' => 'x')
  end

  # MOTIVO (#3176): os ids da WAHA e o controle da Prospecção não dizem nada à IA de atendimento e do funil.
  it 'tira dos valores as chaves internas, com ou sem definição, e não dá significado a elas', :aggregate_failures do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'waha_whatsapp_chat_id',
                                         attribute_display_name: 'Chat id')
    atributos = { 'placa' => 'ABC1D23', 'waha_whatsapp_chat_id' => '5511900000000@c.us', 'autonomia_prospecting_lead_id' => 7,
                  'autonomia_prospecting_rating' => 4.5 }

    expect(leitor.valores(atributos, 'contact_attribute')).to eq('placa' => 'ABC1D23', 'autonomia_prospecting_rating' => 4.5)
    expect(described_class.new(nil).valores(atributos, 'contact_attribute').keys).to eq(%w[placa autonomia_prospecting_rating])
    expect(leitor.significados(%w[waha_whatsapp_chat_id placa], 'contact_attribute').keys).to eq(['placa'])
  end
end
