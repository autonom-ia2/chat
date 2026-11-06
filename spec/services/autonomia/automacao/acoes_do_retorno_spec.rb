require 'rails_helper'

# A porta do passo "criar retorno" (G3, #2629): só o POST crm/follow_ups, e só com as chaves de automações e de funis de
# quem ligou, reconferidas a cada execução (#2633). O motivo vai como chave, traduzida pela própria SemPermissao.
# O resto (Pundit do retorno, card e conversa que a pessoa enxerga) é do endpoint, provado no passo_de_retorno_spec.
RSpec.describe Autonomia::Automacao::AcoesDoRetorno, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:definicao) { create(:autonomia_automacao, account: account, ligada_por: admin) }
  let(:execucao) { create(:autonomia_automacao_execucao, versao: create(:autonomia_automacao_versao, automacao: definicao), alvo: conversa) }

  after { Current.reset }

  def acoes(quem = admin)
    described_class.new(execucao: execucao, account_user: account.account_users.find_by(user: quem))
  end

  it 'recusa qualquer outra ação, mesmo da lista permitida e para o administrador' do
    expect { acoes.send(:garantir_permitida!, 'POST conversations/:id/toggle_priority') }
      .to raise_error(Autonomia::Guide::Acoes::Recusada, I18n.t('autonomia.automacao.motivos.acao_fora'))
  end

  it 'recusa quem ligou sem a chave de automações, com o motivo dela' do
    expect { acoes(agente).send(:garantir_permitida!, Autonomia::Automacao::PassoDeRetorno::ACAO) }
      .to raise_error(Autonomia::Automacao::AcoesDoMotor::SemPermissao) { |erro| expect(erro.motivo).to eq('quem_ligou_sem_permissao') }
  end

  it 'recusa quem ligou sem a chave de funis, no EE' do
    skip 'só no EE' unless ChatwootApp.enterprise?

    funcao = create(:custom_role, account: account, permissions: %w[automation_manage crm_view crm_manage_cards])
    agente.account_users.find_by(account: account).update!(custom_role: funcao)

    expect { acoes(agente).send(:garantir_permitida!, Autonomia::Automacao::PassoDeRetorno::ACAO) }
      .to raise_error(Autonomia::Automacao::AcoesDoMotor::SemPermissao) { |erro| expect(erro.motivo).to eq('sem_chave_de_funis') }
  end

  it 'libera o retorno para quem tem a chave' do
    expect { acoes.send(:garantir_permitida!, Autonomia::Automacao::PassoDeRetorno::ACAO) }.not_to raise_error
  end
end
