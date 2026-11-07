require 'rails_helper'

# G15 (#2414): as agentes de IA que o passo "Passar para a agente de IA" oferece no editor. Pede `automation_manage`,
# como montar a automação, e devolve só id e nome (parecer de Funções): nada de prompt, configuração, caixas ou custo.
RSpec.describe 'Api::V1::Accounts::Autonomia::AutomacoesIa agentes_de_ia', :automacao_motor, type: :request do
  include_context 'with crm responsible agent'

  let(:caminho) { "/api/v1/accounts/#{account.id}/autonomia/automacoes/agentes_de_ia" }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_editor')
  end

  def pedir(quem) = get(caminho, headers: quem.create_new_auth_token, as: :json)

  def com_funcao(*permissoes)
    create(:user, account: account, role: :agent).tap do |pessoa|
      pessoa.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: permissoes))
    end
  end

  it 'devolve só id e nome das agentes que recebem conversa numa caixa da conta', :aggregate_failures do
    pedir(admin)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['agentes']).to contain_exactly({ 'id' => agente_da_porta.id, 'name' => 'Porta' },
                                                               { 'id' => area.id, 'name' => 'Área Suporte' })
  end

  it 'com automation_manage, a função também vê a lista' do
    pedir(com_funcao('automation_manage'))

    expect(response.parsed_body['agentes'].size).to eq(2)
  end

  it 'sem automation_manage, recusa' do
    pedir(com_funcao('automation_view'))

    expect(response).to have_http_status(:unauthorized)
  end
end
