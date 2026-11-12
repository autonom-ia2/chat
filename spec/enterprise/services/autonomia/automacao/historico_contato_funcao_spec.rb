require 'rails_helper'

# #2731: o contato do histórico segue a política do contato. Na função sem contact_view (EE, #1849) a base de contatos
# fica fechada, e o histórico mostra só o tipo, sem nome nem link; com contact_view, o nome e o link.
RSpec.describe Autonomia::Automacao::Historico do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:automacao) { create(:autonomia_automacao, account: account) }
  let(:versao) { create(:autonomia_automacao_versao, automacao: automacao) }
  let(:contato) { create(:contact, account: account, name: 'Maria') }

  def com_funcao(*permissoes)
    funcao = create(:custom_role, account: account, permissions: permissoes)
    agente.account_users.find_by(account: account).update!(role: :agent, custom_role: funcao)
  end

  def alvo_visto
    create(:autonomia_automacao_execucao, versao: versao, alvo: contato, chave_gatilho: 'a')
    described_class.new(automacao: automacao, usuario: agente, com_valores: true, pagina: 1).resultado[:execucoes].first[:alvo]
  end

  it 'função sem contact_view vê só o tipo do contato' do
    com_funcao('automation_view')

    expect(alvo_visto).to eq(tipo: 'contato', visivel: false)
  end

  it 'função com contact_view vê o nome e o link do contato' do
    com_funcao('automation_view', 'contact_view')

    expect(alvo_visto).to eq(tipo: 'contato', visivel: true, nome: 'Maria', link: "accounts/#{account.id}/contacts/#{contato.id}")
  end
end
