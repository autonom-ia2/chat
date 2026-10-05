require 'rails_helper'

# #1006 (Q2): which contact custom attribute each extra column fills.
RSpec.describe ContactImports::AttributeColumns, :aggregate_failures do
  let(:account) { create_account_and_user.first }

  def columns(headers)
    described_class.new(account, headers).perform.map(&:to_h)
  end

  it 'builds a new key from the header without accents, case or spaces' do
    expect(columns(['Data de Vencimento', 'Plano Contratado'])).to eq(
      [
        { 'column' => 'Data de Vencimento', 'key' => 'data_de_vencimento', 'label' => 'Data de Vencimento', 'existing' => false, 'type' => 'text' },
        { 'column' => 'Plano Contratado', 'key' => 'plano_contratado', 'label' => 'Plano Contratado', 'existing' => false, 'type' => 'text' }
      ]
    )
  end

  it 'fills an existing contact attribute found by key or by display name' do
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'vencimento',
                                                 attribute_display_name: 'Vencimento da apólice', attribute_display_type: :date)
    account.custom_attribute_definitions.create!(attribute_model: :contact_attribute, attribute_key: 'cpf_cliente',
                                                 attribute_display_name: 'CPF', attribute_display_type: :text)

    expect(columns(%w[Vencimento CPF])).to eq(
      [
        { 'column' => 'Vencimento', 'key' => 'vencimento', 'label' => 'Vencimento da apólice', 'existing' => true, 'type' => 'date' },
        { 'column' => 'CPF', 'key' => 'cpf_cliente', 'label' => 'CPF', 'existing' => true, 'type' => 'text' }
      ]
    )
  end

  it 'ignores conversation attributes with the same key' do
    account.custom_attribute_definitions.create!(attribute_model: :conversation_attribute, attribute_key: 'plano',
                                                 attribute_display_name: 'Plano', attribute_display_type: :text)

    expect(columns(['Plano']).sole).to include('key' => 'plano', 'existing' => false)
  end

  it 'never takes a standard contact field and never repeats a key in the file' do
    expect(columns(['City', 'Plano', 'plano', '!!!']).pluck('key')).to eq(%w[city_2 plano plano_2 coluna])
  end
end
