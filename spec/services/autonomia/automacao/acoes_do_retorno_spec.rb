require 'rails_helper'

# A porta do passo "criar retorno" (G3, #2629): só o POST crm/follow_ups, e só com a chave de automações de quem ligou.
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

  it 'recusa quem ligou sem a chave de automações' do
    expect { acoes(agente).send(:garantir_permitida!, Autonomia::Automacao::PassoDeRetorno::ACAO) }
      .to raise_error(Autonomia::Automacao::AcoesDoMotor::SemPermissao)
  end

  it 'libera o retorno para quem tem a chave' do
    expect { acoes.send(:garantir_permitida!, Autonomia::Automacao::PassoDeRetorno::ACAO) }.not_to raise_error
  end
end
