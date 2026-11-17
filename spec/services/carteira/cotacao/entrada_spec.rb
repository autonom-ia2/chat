require 'rails_helper'

# E8 (#2901): a entrada da cotação montada da carteira nunca sai completa sem o que a busca paga do segurado (`quote/enrich`)
# acharia pelo documento. Assim a conferência da ferramenta nunca a chama no caminho da carteira. Tudo fictício.
RSpec.describe Carteira::Cotacao::Entrada do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:conexao) { Autonomia::Insurance::Connection.create!(account: account, username: 'corretora@exemplo.test', password: 'senha-exemplo') }

  before do
    enable_test_encryption!
    allow(Autonomia::Agents::Tools::Native::InsuranceQuote).to receive(:schema_da_conexao).and_return('campos' => [])
  end

  def entrada_de(pessoa, tipo)
    seguro = criar_apolice(pessoa, tipo: tipo, seguradora: 'HDI', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date)
    described_class.new(seguro, conexao).call
  end

  it 'auto: sem nascimento e sexo na carteira, os dois faltam' do
    marina = create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023')

    expect(entrada_de(marina, 'auto').faltam).to include('insured.birthDate', 'insured.gender')
  end

  it 'outros ramos: sem o nome do segurado, ele falta mesmo quando o formulário do ramo não o pede' do
    sem_nome = create(:contact, account: account, name: '', phone_number: '+5511900000024')

    expect(entrada_de(sem_nome, 'residencial').faltam).to include('segurado.nome')
  end

  it 'outros ramos: com o nome, ele não falta' do
    marina = create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023')

    expect(entrada_de(marina, 'residencial').faltam).not_to include('segurado.nome')
  end
end
