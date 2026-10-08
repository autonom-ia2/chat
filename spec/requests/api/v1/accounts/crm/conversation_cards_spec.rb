require 'rails_helper'

RSpec.describe 'CRM conversation subjects API', type: :request do
  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create_account_and_user.first }
  let(:admin) { account.users.first }
  let(:agent) { create_crm_agent(account: account).first }
  let(:inbox) { create_crm_inbox(account: account, members: [agent]) }
  let(:contact) { account.contacts.create!(name: 'Lead Dois Assuntos', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}" }

  def create_subject(title, new_subject: true)
    post "/api/v1/accounts/#{account.id}/crm/cards/from_conversation",
         params: { conversation_display_id: conversation.display_id, new_subject: new_subject,
                   card: { pipeline_id: pipeline.id, title: title } },
         headers: auth_headers(agent)
    response.parsed_body.dig('payload', 'id')
  end

  it 'lists the conversation subjects with the most recent one as current' do
    first_id = create_subject('Agentes de IA', new_subject: false)
    second_id = create_subject('Chat2You')

    get "#{base_url}/cards", headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.pluck('id')).to eq([second_id, first_id])
    expect(payload.pluck('current')).to eq([true, false])
    expect(payload.first).to include('title' => 'Chat2You', 'pipeline_name' => pipeline.name, 'status' => 'open')
  end

  it 'switches the current subject and the conversation badge follows it' do
    first_id = create_subject('Agentes de IA', new_subject: false)
    create_subject('Chat2You')

    post "#{base_url}/focus", params: { card_id: first_id }, headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    get "#{base_url}/cards", headers: auth_headers(agent)
    expect(response.parsed_body['payload'].first).to include('id' => first_id, 'current' => true)

    get "/api/v1/accounts/#{account.id}/crm/conversations/card_stages",
        params: { conversation_ids: [conversation.display_id] }, headers: auth_headers(agent)
    badge = response.parsed_body.dig('payload', conversation.display_id.to_s)
    expect(badge).to include('card_id' => first_id, 'subjects_count' => 2)
  end

  it 'moves the current subject to an open one when the focused card is closed, as automations see it' do
    first_id = create_subject('Agentes de IA', new_subject: false)
    second_id = create_subject('Chat2You')
    account.crm_cards.find(second_id).update!(status: :won)

    get "#{base_url}/cards", headers: auth_headers(agent)

    expect(response.parsed_body['payload'].first).to include('id' => first_id, 'current' => true)
    expect(Crm::Cards::ConversationCardFinder.new(account: account).find(conversation).id).to eq(first_id)
  end

  it 'does not leak the title of a card the agent cannot see in the list badge' do
    other_inbox = create_crm_inbox(account: account, name: 'Caixa restrita')
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, contact: contact, inbox: other_inbox,
                              primary_conversation: conversation, title: 'Assunto restrito')

    get "/api/v1/accounts/#{account.id}/crm/conversations/card_stages",
        params: { conversation_ids: [conversation.display_id] }, headers: auth_headers(agent)

    expect(response.body).not_to include('Assunto restrito')
    get "#{base_url}/card", headers: auth_headers(agent)
    expect(response.body).not_to include('Assunto restrito')
  end

  it 'does not make a closed card the current subject' do
    first_id = create_subject('Agentes de IA', new_subject: false)
    account.crm_cards.find(first_id).update!(status: :won)

    post "#{base_url}/focus", params: { card_id: first_id }, headers: auth_headers(agent)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'refuses a card that does not belong to the conversation' do
    create_subject('Agentes de IA', new_subject: false)
    other_conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    other_card = account.crm_cards.create!(pipeline: pipeline, stage: pipeline_and_stage.last, contact: contact,
                                           primary_conversation: other_conversation, title: 'Outra conversa')

    post "#{base_url}/focus", params: { card_id: other_card.id }, headers: auth_headers(agent)

    expect(response).to have_http_status(:not_found)
  end

  it 'hides the conversation from an agent outside the inbox' do
    create_subject('Agentes de IA', new_subject: false)
    outsider = create_crm_agent(account: account, name: 'Fora da caixa').first

    get "#{base_url}/cards", headers: auth_headers(outsider)

    expect(response).to have_http_status(:unauthorized)
  end
end
