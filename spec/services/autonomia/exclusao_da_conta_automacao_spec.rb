require 'rails_helper'

# A automação aponta para a versão ativa e a versão aponta para a automação: a ordem das ETAPAS mais o SET NULL da
# versão ativa têm de apagar as quatro tabelas sem esbarrar nas chaves (#2414, F2 #2452).
RSpec.describe Autonomia::ExclusaoDaConta do
  it 'apaga automação, versões, execuções e registros da conta, e só dela' do
    registro = create(:autonomia_automacao_registro)
    automacao = registro.automacao
    automacao.update!(versao_ativa: registro.execucao.versao)
    de_outra_conta = create(:autonomia_automacao_registro)

    described_class.new(automacao.account).perform

    modelos = [Autonomia::Automacao::Registro, Autonomia::Automacao::Execucao, Autonomia::Automacao::Versao,
               Autonomia::Automacao::Definicao]
    expect(modelos.map { |modelo| modelo.where(account_id: automacao.account_id).count }).to eq([0, 0, 0, 0])
    expect(modelos.map { |modelo| modelo.where(account_id: de_outra_conta.account_id).count }).to eq([1, 1, 1, 1])
  end
end
