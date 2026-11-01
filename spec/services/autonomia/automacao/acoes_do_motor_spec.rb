require 'rails_helper'

# A porta da ação da automação (#2414 F3, D2): a lista de ações permitidas e a chave de automações liberam; a caixa, o
# Pundit e a conta seguem valendo pelo endpoint.
RSpec.describe Autonomia::Automacao::AcoesDoMotor, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:execucao) { create(:autonomia_automacao_execucao, versao: create(:autonomia_automacao_versao, automacao: definicao), alvo: conversa) }
  let(:definicao) { create(:autonomia_automacao, account: account, ligada_por: agente) }
  let(:prioridade) { { caminho: { id: conversa.display_id }, corpo: { priority: 'high' }, descricao: 'Marcar a prioridade' } }

  after { Current.reset }

  def acoes
    described_class.new(execucao: execucao, account_user: account.account_users.find_by(user: definicao.ligada_por))
  end

  it 'recusa o agente sem a chave de automações' do
    expect { acoes.executar('POST conversations/:id/toggle_priority', prioridade) }
      .to raise_error(Autonomia::Guide::Acoes::Recusada, I18n.t('autonomia.automacao.motivos.quem_ligou_sem_permissao'))
  end

  it 'recusa a ação fora da lista, mesmo para o administrador' do
    definicao.update!(ligada_por: admin)

    expect { acoes.executar('DELETE labels/:id', { caminho: { id: 1 } }) }.to raise_error(Autonomia::Guide::Acoes::Recusada)
  end

  # Pedido da Automação era 403; a plataforma responde 401 ao Pundit::NotAuthorizedError (ver ApplicationController).
  # O motor trata os dois do mesmo jeito: pausa (F3.7).
  it 'agente com a chave mas sem a caixa: a própria plataforma recusa com 401', :aggregate_failures do
    funcao = create(:custom_role, account: account, permissions: %w[automation_manage conversation_manage])
    account.account_users.find_by(user: agente).update!(custom_role: funcao)

    instancia = acoes
    resultado = instancia.executar('POST conversations/:id/toggle_priority', prioridade)

    expect([resultado.ok, instancia.codigo]).to eq([false, 401])
    expect(conversa.reload.priority).to be_nil
  end
end
