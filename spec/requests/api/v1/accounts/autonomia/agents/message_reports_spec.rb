require 'rails_helper'

# #284 — "resposta errada": o atendente (não só admin) reporta uma mensagem do agente Autonom.ia.
# Reusa Captain::MessageReport. Só mensagens do AgentBot-espelho carimbadas com autonomia_agent_id.
RSpec.describe 'Autonomia agent message reports', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:autonomia_agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:mirror) { create(:agent_bot, account: account, outgoing_url: nil) }
  let(:agent_message) do
    create(:message, account: account, conversation: conversation, message_type: :outgoing, sender: mirror,
                     content_attributes: { autonomia_agent_id: autonomia_agent.id })
  end
  let(:url) { "/api/v1/accounts/#{account.id}/autonomia/agents/message_reports" }
  let(:valid_params) { { message_id: agent_message.id, report_reason: 'incorrect_information', description: 'Prazo errado.' } }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  before { create(:inbox_member, user: agent_user, inbox: inbox) }

  it 'lets an agent of the account report an Autonomia agent reply' do
    expect do
      post url, params: valid_params, headers: agent_user.create_new_auth_token, as: :json
    end.to change(Captain::MessageReport, :count).by(1)

    report = Captain::MessageReport.last
    expect(response).to have_http_status(:success)
    expect(report).to have_attributes(message_id: agent_message.id, conversation_id: conversation.id,
                                      user_id: agent_user.id, report_reason: 'incorrect_information')
    expect(response.parsed_body['report_reason']).to eq('incorrect_information')
  end

  it 'rejects messages that were not posted by an Autonomia agent' do
    human_message = create(:message, account: account, conversation: conversation, message_type: :outgoing)

    expect do
      post url, params: valid_params.merge(message_id: human_message.id),
                headers: agent_user.create_new_auth_token, as: :json
    end.not_to change(Captain::MessageReport, :count)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects an invalid reason' do
    post url, params: valid_params.merge(report_reason: 'nope'), headers: agent_user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'does not let an agent without access to the conversation report' do
    outsider = create(:user, account: account, role: :agent)

    post url, params: valid_params, headers: outsider.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(Captain::MessageReport.count).to eq(0)
  end

  it 'returns 404 for a message of another account' do
    other_message = create(:message)

    post url, params: valid_params.merge(message_id: other_message.id), headers: agent_user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'is invisible when the feature is off for the account' do
    account.update!(internal_attributes: { 'autonomia_agents_enabled' => false })

    post url, params: valid_params, headers: agent_user.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'requires authentication' do
    post url, params: valid_params, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
