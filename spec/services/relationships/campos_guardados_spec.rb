require 'rails_helper'

# #3082 — apagar campo de pessoa ou empresa é "guardar escondido".
RSpec.describe Relationships::CamposGuardados do
  let(:account) { create(:account) }
  let(:guardados) { described_class.new(account.reload).lista }

  def campo(**extra)
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'placa',
                                         attribute_display_name: 'Placa', attribute_description: 'Placa do carro',
                                         attribute_display_type: 'text', **extra)
  end

  it 'guarda o campo apagado e deixa o valor na pessoa' do
    definicao = campo
    contato = create(:contact, account: account, custom_attributes: { 'placa' => 'ABC1D23' })

    definicao.destroy!

    expect(guardados).to contain_exactly(
      a_hash_including('attribute_key' => 'placa', 'attribute_model' => 'contact_attribute', 'attribute_display_name' => 'Placa',
                       'attribute_display_type' => 'text', 'attribute_description' => 'Placa do carro')
    )
    expect(contato.reload.custom_attributes['placa']).to eq('ABC1D23')
  end

  it 'tira a anotação quando o campo volta com a mesma chave' do
    campo.destroy!
    expect(guardados.size).to eq(1)

    campo(attribute_display_name: 'Placa do carro')

    expect(guardados).to be_empty
  end

  it 'guarda também o campo da empresa e anota o mesmo campo uma vez só' do
    2.times { campo(attribute_model: 'company_attribute').destroy! }

    expect(guardados).to contain_exactly(a_hash_including('attribute_model' => 'company_attribute'))
  end

  it 'não guarda campo de conversa' do
    campo(attribute_model: 'conversation_attribute').destroy!

    expect(guardados).to be_empty
  end

  it 'mantém só os mais recentes' do
    stub_const("#{described_class}::LIMITE", 2)
    %w[a b c].each { |chave| campo(attribute_key: chave, attribute_display_name: chave).destroy! }

    expect(guardados.pluck('attribute_key')).to eq(%w[c b])
  end
end
