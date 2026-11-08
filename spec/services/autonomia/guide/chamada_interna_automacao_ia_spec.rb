require 'rails_helper'

# #2500 F7: o Guia monta a automação pela mesma rota do editor (ChamadaInterna). Sem a flag da F7, o passo de IA é
# recusado ali também.
RSpec.describe Autonomia::Guide::ChamadaInterna do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:resumir) { { id: 'p1', tipo: 'resumir', le: ['mensagens_recentes'], linhas: 3, destino: 'nota' } }

  after { Current.reset }

  def criar_pelo_guia
    described_class.new(user: admin).chamar(
      'POST', "/api/v1/accounts/#{account.id}/autonomia/automacoes",
      corpo: { nome: 'Resumo', receita: { gatilho: { tipo: 'conversa.resolvida' }, passos: [resumir] } }
    )
  end

  before { account.enable_features!('automacao_editor', 'automacao_fundacao', 'automacao_motor') }

  it 'recusa passo de IA sem a flag da F7, com 422 e sem gravar', :aggregate_failures do
    expect { criar_pelo_guia }.not_to change(Autonomia::Automacao::Definicao, :count)
    expect(criar_pelo_guia.codigo).to eq('422')
  end

  it 'grava com a flag da F7 ligada' do
    account.enable_features!('automacao_ia')

    expect(criar_pelo_guia.codigo).to eq('201')
  end
end
