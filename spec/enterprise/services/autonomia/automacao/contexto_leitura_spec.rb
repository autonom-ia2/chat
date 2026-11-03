require 'rails_helper'

# #2499 (parecer de Funções no #2508): ver o alvo é leitura e agir nele é escrita. Pega a função só de leitura
# (conversation_view, #1800) vendo "Uma conversa" no histórico, contra o for_reading da lista; e o motor agindo como
# quem só lê.
RSpec.describe Autonomia::Automacao::Contexto do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: create(:user, account: account, role: :agent)) }
  let(:funcao) { create(:custom_role, account: account, permissions: %w[conversation_view automation_view]) }

  before do
    create(:inbox_member, user: agente, inbox: inbox)
    agente.account_users.find_by(account: account).update!(role: :agent, custom_role: funcao)
  end

  it 'função só de leitura: vê a conversa, mas o motor não age nela como essa pessoa', :aggregate_failures do
    definicao = create(:autonomia_automacao, account: account, ligada_por: agente)

    expect(described_class.de(conversa).visivel_para?(agente)).to be(true)
    expect(Autonomia::Automacao::Acesso.new(definicao).alcanca?(conversa)).to be(false)
  end
end
