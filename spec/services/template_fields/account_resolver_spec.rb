require 'rails_helper'

RSpec.describe TemplateFields::AccountResolver do
  let(:account) { create(:account, name: 'Clínica Bem-Estar') }

  def values
    resolver = described_class.new(account)
    resolver.keys.index_with { |key| resolver.value(key) }
  end

  it 'reads the footer of the default brand kit' do
    create(:brand_kit, account: account, is_default: true, appearance: {
             footer: { company_name: 'Bem-Estar Saúde', address: 'Rua das Flores, 100', phone: '(11) 3333-4444',
                       website: 'https://bemestar.com.br' }
           })

    expect(values).to eq(
      'minha_empresa.nome' => 'Bem-Estar Saúde', 'minha_empresa.endereco' => 'Rua das Flores, 100',
      'minha_empresa.telefone' => '(11) 3333-4444', 'minha_empresa.site' => 'https://bemestar.com.br'
    )
  end

  it 'falls back to the account name and leaves the rest empty without a default kit' do
    create(:brand_kit, account: account, is_default: false)

    expect(values).to eq('minha_empresa.nome' => 'Clínica Bem-Estar', 'minha_empresa.endereco' => nil,
                         'minha_empresa.telefone' => nil, 'minha_empresa.site' => nil)
  end

  it 'ignores an archived kit and the kit of another account' do
    create(:brand_kit, account: create(:account), is_default: true)

    expect(values['minha_empresa.nome']).to eq('Clínica Bem-Estar')
  end
end
