require 'rails_helper'

# #2000 (revisão) — o cartão da semana e a lista que ele abre contam o mesmo conjunto também para quem não é
# administrador: uma função com autonomia_view e conversation_view (só lê, #1800) que só enxerga uma caixa vê, nos dois, só as conversas dessa caixa.
RSpec.describe 'Autonomia: o cartão da semana é a lista, para uma função personalizada', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:caixa_dela) { create(:inbox, account: account) }
  let(:outra_caixa) { create(:inbox, account: account) }
  let(:bia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:espelho) { create(:agent_bot, account: account) }
  let(:pessoa) do
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: %w[autonomia_view conversation_view])
    user.account_users.find_by(account: account).update!(custom_role: role)
    create(:inbox_member, user: user, inbox: caixa_dela)
    user
  end

  around do |example|
    with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run }
  end

  before do
    account.enable_features!('autonomia_agents_journey')
    Autonomia::Agents::AgentInbox.create!(agent: bia, inbox: create(:inbox, account: account), account: account, agent_bot: espelho)
    [caixa_dela, outra_caixa].each do |caixa|
      chat = create(:conversation, account: account, inbox: caixa)
      create(:message, account: account, inbox: caixa, conversation: chat, message_type: :outgoing, sender: espelho)
    end
  end

  it 'conta no cartão e mostra na lista só as conversas que a pessoa pode abrir' do
    headers = pessoa.create_new_auth_token
    get "/api/v1/accounts/#{account.id}/autonomia/numeros_da_semana", params: { agent_id: bia.id }, headers: headers, as: :json
    cartao = response.parsed_body['payload'].first['answered']
    get "/api/v1/accounts/#{account.id}/autonomia/agents/#{bia.id}/analytics/conversations",
        params: { range: '7d', metric: 'respondidas' }, headers: headers, as: :json
    lista = response.parsed_body['payload'].map { |linha| linha.dig('conversation', 'id') }

    expect(response).to have_http_status(:success)
    expect(lista.size).to eq(cartao)
    expect(cartao).to eq(1)
    expect(Conversation.where(id: lista).pluck(:inbox_id)).to eq([caixa_dela.id])
  end
end
