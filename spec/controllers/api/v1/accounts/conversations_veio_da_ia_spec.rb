require 'rails_helper'

# #2067: a conversa diz ao painel de qual agente de IA ela veio (meta.veio_da_ia), na leitura, na lista e no evento ao
# vivo; o "Devolver para" usa a atribuição de robô de hoje.
RSpec.describe 'Veio da IA no payload da conversa', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:bot) { create(:agent_bot, account: account, name: 'Lia') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open).reload }
  let(:esperado) { { 'id' => bot.id, 'name' => 'Lia' } }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    conversation.update!(ai_assignee: bot)
    Current.user = ana
    conversation.update!(assignee: ana) # a pessoa assume: o registro grava Lia → Ana
    Current.reset
  end

  def get_json(url)
    get url, headers: ana.create_new_auth_token, as: :json
    response.parsed_body
  end

  it 'na conversa lida sozinha, na lista e no evento ao vivo', :aggregate_failures do
    show = get_json(api_v1_account_conversation_url(account_id: account.id, id: conversation.display_id))
    expect(show.dig('meta', 'veio_da_ia')).to eq(esperado)

    lista = get_json(api_v1_account_conversations_url(account_id: account.id, assignee_type: 'all'))
    expect(lista.dig('data', 'payload').first.dig('meta', 'veio_da_ia')).to eq(esperado)

    expect(conversation.reload.push_event_data.dig(:meta, :veio_da_ia)).to eq(id: bot.id, name: 'Lia')
    expect(conversation.webhook_data[:meta]).not_to have_key(:veio_da_ia)
  end

  it 'Devolver para a IA: a atribuição de robô tira a pessoa e a linha some', :aggregate_failures do
    post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
         params: { assignee_id: bot.id, assignee_type: 'AgentBot' }, headers: ana.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(conversation.reload).to have_attributes(assignee_id: nil, ai_assignee: bot)
    expect(conversation.push_event_data.dig(:meta, :veio_da_ia)).to be_nil
  end
end
