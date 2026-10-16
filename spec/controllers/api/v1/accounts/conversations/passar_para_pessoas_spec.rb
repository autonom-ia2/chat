require 'rails_helper'

# #1140 (correção 5) — "Passar para…": a lista de pessoas vem do servidor com a mesma regra que ele usa para aceitar a
# passagem (quem pode ser atribuído na caixa e vê a conversa pelo acesso por funil). A tela não oferece quem será recusado.
RSpec.describe 'Conversation Passar para API: pessoas', type: :request do
  include_context 'with crm responsible agent'

  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Lima') }
  let(:url) { "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/passar_para" }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    create(:inbox_member, inbox: inbox, user: ana)
    create(:inbox_member, inbox: inbox, user: bruno)
    conversation.update!(assignee: ana, ai_assignee: nil)
  end

  def ids_na_lista
    get url, headers: ana.create_new_auth_token
    response.parsed_body['pessoas'].pluck('id')
  end

  it 'lists the people of the inbox with name, photo and presence', :aggregate_failures do
    get url, headers: ana.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['pessoas'].pluck('id')).to include(ana.id, bruno.id)
    expect(response.parsed_body['pessoas'].find { |pessoa| pessoa['id'] == bruno.id })
      .to include('name' => 'Bruno Lima', 'thumbnail' => anything, 'availability_status' => anything)
  end

  # Pega: oferecer quem o servidor recusa (o erro só aparecia depois do clique).
  it 'leaves out who only sees their own conversations, and the server refuses the same person', :aggregate_failures do
    Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: bruno, all_pipelines: true, triage: true, only_own: true)

    expect(ids_na_lista).to include(ana.id)
    expect(ids_na_lista).not_to include(bruno.id)

    post url, params: { destino: { tipo: 'pessoa', id: bruno.id } }, headers: ana.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['codigo']).to eq('pessoa_fora_da_caixa')
  end

  # Pega: a lista e a aceitação divergirem. Quem aparece na lista o servidor aceita.
  it 'accepts whoever it lists', :aggregate_failures do
    expect(ids_na_lista).to include(bruno.id)

    post url, params: { destino: { tipo: 'pessoa', id: bruno.id } }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(conversation.reload.assignee_id).to eq(bruno.id)
  end
end
