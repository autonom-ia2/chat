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
end
