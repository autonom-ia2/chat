require 'rails_helper'

RSpec.describe 'CRM cards API', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  it 'blocks endpoints when the feature flag is disabled' do
    account, user = create_account_and_user
    ENV['CRM_KANBAN_ENABLED'] = 'false'

    get "/api/v1/accounts/#{account.id}/crm/cards", headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('crm.disabled')
  end

  it 'rejects malformed company and score filter parameters at the request boundary' do
    account, user = create_account_and_user
    pipeline, = create_crm_pipeline(account: account, user: user)
    headers = auth_headers(user)

    get "/api/v1/accounts/#{account.id}/crm/cards", params: { company_id: ['1'] }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.invalid_filter_parameters')

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: { pipeline_id: pipeline.id, company_id: '0' }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.invalid_filter_parameters')

    get "/api/v1/accounts/#{account.id}/crm/cards", params: { score_min: '80', score_max: '20' }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('crm.invalid_filter_parameters')
  end

  it 'returns and filters the account-scoped company resolved for each card' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    contact_company = create(:company, account: account, name: 'Empresa do contato')
    prospecting_company = create(:company, account: account, name: 'Empresa da prospecção')
    contact = account.contacts.create!(name: 'Pessoa da oportunidade', company: contact_company)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Prospecção da empresa',
      contact: contact,
      metadata: { 'autonomia_prospecting' => { 'company' => { 'id' => prospecting_company.id } } }
    )
    no_company_card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Sem empresa')

    get "/api/v1/accounts/#{account.id}/crm/cards", params: { search: 'Empresa da prospecção' }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.pluck('id')).to eq([card.id])
    expect(payload.first['company']).to eq('id' => prospecting_company.id, 'name' => prospecting_company.name)

    get "/api/v1/accounts/#{account.id}/crm/cards", params: { company_id: 'none' }, headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([no_company_card.id])

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'company')).to eq(
      'id' => prospecting_company.id,
      'name' => prospecting_company.name
    )
  end

  it 'rejects noncanonical numeric filters instead of coercing them' do
    account, user = create_account_and_user
    headers = auth_headers(user)
    ['0x10', '1_0', '+1', ' 1', '01'].each do |value|
      get "/api/v1/accounts/#{account.id}/crm/cards", params: { company_id: value }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      get "/api/v1/accounts/#{account.id}/crm/cards", params: { score_min: value }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'creates a standalone card without contact, conversation or inbox' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: { pipeline_id: pipeline.id, stage_id: stage.id, title: 'Renovação interna' } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['is_standalone']).to be(true)
    expect(payload['contact_id']).to be_nil
    expect(payload['conversation_id']).to be_nil
    expect(payload['inbox_id']).to be_nil
    expect(account.crm_activities.where(event_type: 'create').count).to eq(1)
  end

  it 'creates a manual card linked to an existing account contact' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    contact = account.contacts.create!(name: 'Cliente Manual', phone_number: '+5511987654321')

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: { pipeline_id: pipeline.id, stage_id: stage.id, contact_id: contact.id, title: 'Cliente Manual' } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['is_standalone']).to be(false)
    expect(payload['contact_id']).to eq(contact.id)
    expect(payload['conversation_id']).to be_nil
    expect(payload['inbox_id']).to be_nil
  end

  it 'creates a card from conversation and fills available Chatwoot data' do
    account, user = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Maria Silva', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: user)

    post "/api/v1/accounts/#{account.id}/crm/cards/from_conversation",
         params: { conversation_id: conversation.id, pipeline_id: pipeline.id },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['conversation_id']).to eq(conversation.id)
    expect(payload['contact_id']).to eq(contact.id)
    expect(payload['inbox_id']).to eq(inbox.id)
    expect(payload['owner_id']).to eq(agent.id)
    expect(payload['title']).to eq('Maria Silva')
    expect(account.crm_card_conversations.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'reuses an existing card when creating from the same conversation display id' do
    account, user = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Lead Repetido', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: user)

    post "/api/v1/accounts/#{account.id}/crm/cards/from_conversation",
         params: { conversation_display_id: conversation.display_id, card: { pipeline_id: pipeline.id } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    first_card_id = response.parsed_body['payload']['id']

    post "/api/v1/accounts/#{account.id}/crm/cards/from_conversation",
         params: { conversation_display_id: conversation.display_id, card: { pipeline_id: pipeline.id } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['id']).to eq(first_card_id)
    expect(payload['conversation']['display_id']).to eq(conversation.display_id)
    expect(account.crm_cards.where(conversation_id: conversation.id).count).to eq(1)
    expect(account.crm_card_conversations.where(conversation_id: conversation.id).count).to eq(1)
  end

  it 'creates a second open card in the same conversation and pipeline when a new subject is requested' do
    account, user = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    contact = account.contacts.create!(name: 'Cliente Dois Assuntos', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: user)
    url = "/api/v1/accounts/#{account.id}/crm/cards/from_conversation"

    post url, params: { conversation_display_id: conversation.display_id, card: { pipeline_id: pipeline.id, title: 'Agentes de IA' } },
              headers: auth_headers(user)
    first_card_id = response.parsed_body['payload']['id']

    post url, params: { conversation_display_id: conversation.display_id, new_subject: true,
                        card: { pipeline_id: pipeline.id, title: 'Chat2You' } },
              headers: auth_headers(user)

    expect(response).to have_http_status(:created)
    second_card_id = response.parsed_body['payload']['id']
    expect(second_card_id).not_to eq(first_card_id)
    expect(account.crm_cards.open.where(conversation_id: conversation.id, pipeline_id: pipeline.id).pluck(:title))
      .to contain_exactly('Agentes de IA', 'Chat2You')

    get "/api/v1/accounts/#{account.id}/crm/conversations/#{conversation.display_id}/card", headers: auth_headers(user)
    expect(response.parsed_body.dig('payload', 'card_id')).to eq(second_card_id)

    get "/api/v1/accounts/#{account.id}/crm/conversations/card_stages",
        params: { conversation_ids: [conversation.display_id] }, headers: auth_headers(user)
    expect(response.parsed_body.dig('payload', conversation.display_id.to_s, 'card_id')).to eq(second_card_id)
  end

  it 'moves a card and records an activity' do
    account, user = create_account_and_user
    pipeline, first_stage = create_crm_pipeline(account: account, user: user)
    second_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Mover')

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/move",
         params: { stage_id: second_stage.id },
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    card.reload
    expect(card.stage_id).to eq(second_stage.id)
    expect(card.entered_stage_at).to be_present
    move_activity = card.activities.where(event_type: 'move').last
    expect(move_activity.payload['from_stage_id']).to eq(first_stage.id)
    expect(move_activity.payload['to_stage_id']).to eq(second_stage.id)
  end

  it 'junta os campos do card ao que já estava salvo, e null tira o campo (#1146)' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Onix',
                                     custom_attributes: { 'placa' => 'ABC1D23', 'ano' => 2021, 'cor' => 'prata' })

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { custom_attributes: { ano: 2022, cor: nil } } }, headers: auth_headers(user), as: :json

    expect(response).to have_http_status(:ok)
    expect(card.reload.custom_attributes).to eq('placa' => 'ABC1D23', 'ano' => 2022)
    expect(response.parsed_body.dig('payload', 'custom_attributes')).to eq('placa' => 'ABC1D23', 'ano' => 2022)
  end

  it 'o histórico do PATCH registra só os campos enviados, não o hash inteiro (#1146)' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Onix', custom_attributes: { 'placa' => 'ABC1D23' })

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { custom_attributes: { ano: 2022 } } }, headers: auth_headers(user), as: :json

    expect(card.activities.where(event_type: 'update').last.payload).to eq('custom_attributes' => { 'ano' => 2022 })
  end

  it 'cria o card com os campos enviados e o upsert por external_id junta com o que já existe (#1146)' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    base = { pipeline_id: pipeline.id, stage_id: stage.id, title: 'Onix', external_id: 'erp-7' }

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: base.merge(custom_attributes: { placa: 'ABC1D23' }) }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:created)
    card = account.crm_cards.find_by!(external_id: 'erp-7')
    expect(card.custom_attributes).to eq('placa' => 'ABC1D23')

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: base.merge(custom_attributes: { ano: 2021 }) }, headers: auth_headers(user), as: :json
    expect(card.reload.custom_attributes).to eq('placa' => 'ABC1D23', 'ano' => 2021)
  end

  it 'does not move a card through the generic update endpoint' do
    account, user = create_account_and_user
    pipeline, first_stage = create_crm_pipeline(account: account, user: user)
    second_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Sem atalho')

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { stage_id: second_stage.id, pipeline_id: pipeline.id, title: 'Atualizado' } },
          headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    card.reload
    expect(card.stage_id).to eq(first_stage.id)
    expect(card.title).to eq('Atualizado')
    expect(card.activities.where(event_type: 'move')).to be_blank
  end

  # O drawer envia `score` em toda edição. Marcar manual pela presença da chave congelava a nota da
  # IA quando o vendedor só corrigia o título — o score parava de atualizar sem ninguém tocar nele.
  it 'does not freeze the AI score when only other fields change' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Antigo', score: 82,
      metadata: { 'ai' => { 'score' => { 'value' => 82, 'source' => 'ai' } } }
    )

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { title: 'Novo título', score: 82 } },
          headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(card.reload.metadata.dig('ai', 'score', 'source')).to eq('ai')
  end

  it 'marks the score as manual when the value actually changes' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Lead', score: 82,
      metadata: { 'ai' => { 'score' => { 'value' => 82, 'source' => 'ai' } } }
    )

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { score: 30 } },
          headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    card.reload
    expect(card.score).to eq(30)
    expect(card.metadata.dig('ai', 'score')).to include('source' => 'manual', 'stage_id' => stage.id)
  end

  it 'keeps move idempotent when the target stage is already current' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    entered_stage_at = 2.days.ago
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Mesmo estágio', entered_stage_at: entered_stage_at)

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/move",
         params: { stage_id: stage.id },
         headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    card.reload
    expect(card.entered_stage_at.to_i).to eq(entered_stage_at.to_i)
    expect(card.activities.where(event_type: 'move')).to be_blank
  end

  it 'returns a controlled not found response for nonexistent optional links' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: { pipeline_id: pipeline.id, stage_id: stage.id, contact_id: 99_999_999, title: 'Contato inválido' } },
         headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
  end

  it 'prevents agents without inbox access from reading an inbox card directly' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: 'Sem acesso')

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(agent)

    expect(response).to have_http_status(:not_found)
  end

  it 'returns card detail timeline and linked conversations for admins' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Timeline', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      inbox: inbox,
      primary_conversation: conversation,
      title: 'Lead Timeline'
    )
    account.crm_card_conversations.create!(card: card, conversation: conversation, linked_by: admin, is_primary: true)
    Crm::ActivityLogger.new(
      card: card,
      actor: admin,
      event_type: 'update',
      conversation: conversation,
      payload: { title: 'Lead Timeline' }
    ).perform

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['linked_conversations'].first['display_id']).to eq(conversation.display_id)
    expect(payload['linked_conversations'].first['is_primary']).to be(true)
    expect(payload['activities'].first['event_type']).to eq('update')
    expect(payload['activities'].first['actor_name']).to eq(admin.name)
    expect(payload['activities'].first['payload']['title']).to eq('Lead Timeline')
  end

  it 'returns the primary conversation details for a legacy card without a join row' do
    account, admin = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [admin])
    contact = account.contacts.create!(name: 'Lead Legado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: admin)
    activity_at = 2.hours.ago
    conversation.update!(last_activity_at: activity_at)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      contact: contact,
      inbox: inbox,
      primary_conversation: conversation,
      title: 'Lead Legado'
    )

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    linked_conversation = response.parsed_body.dig('payload', 'linked_conversations').first
    expect(linked_conversation).to include(
      'display_id' => conversation.display_id,
      'inbox_name' => inbox.name,
      'last_activity_at' => conversation.reload.last_activity_at.iso8601,
      'is_primary' => true
    )
  end

  it 'removes raw follow-up errors from card activity payloads for admins' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead seguro')
    retry_at = 1.hour.from_now.iso8601
    Crm::ActivityLogger.new(
      card: card,
      actor: nil,
      event_type: 'ai_followup_failed',
      payload: {
        error: 'provider-secret',
        attempts: 2,
        final: false,
        retry_at: retry_at,
        nested: { send_error: 'nested-provider-secret', keep: 'safe' }
      }
    ).perform

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    activity_payload = response.parsed_body.dig('payload', 'activities').first.fetch('payload')
    expect(activity_payload).to include(
      'attempts' => 2,
      'final' => false,
      'retry_at' => retry_at
    )
    expect(activity_payload).not_to have_key('error')
    expect(activity_payload.dig('nested', 'send_error')).to be_nil
    expect(activity_payload.dig('nested', 'keep')).to eq('safe')
  end

  it 'filters hidden linked conversations from card details for agents' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    hidden_contact = account.contacts.create!(name: 'Lead Oculto', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: hidden_contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Card do agente')
    account.crm_card_conversations.create!(card: card, conversation: hidden_conversation, linked_by: admin)
    Crm::ActivityLogger.new(
      card: card,
      actor: admin,
      event_type: 'update',
      payload: { title: 'Card do agente' }
    ).perform
    Crm::ActivityLogger.new(
      card: card,
      actor: admin,
      event_type: 'update',
      payload: {
        metadata: {
          source_conversation: {
            display_id: "hidden-display-#{hidden_conversation.id}"
          }
        },
        description: 'Sem conversa no payload do agente'
      }
    ).perform
    Crm::ActivityLogger.new(
      card: card,
      actor: admin,
      event_type: 'conversation_linked',
      conversation: hidden_conversation,
      payload: { conversation_id: hidden_conversation.id }
    ).perform

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['linked_conversations']).to be_empty
    expect(payload['activities'].pluck('event_type')).to all(eq('update'))
    expect(payload['activities'].filter_map { |activity| activity['conversation_id'] }).not_to include(hidden_conversation.id)
    expect(payload['activities'].filter_map { |activity| activity.dig('payload', 'conversation_id') }).not_to include(hidden_conversation.id)
    expect(payload['activities'].filter_map { |activity| activity.dig('payload', 'metadata', 'source_conversation') }).to be_empty
  end

  it 'sanitizes hidden primary conversation data from card details for agents' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    hidden_contact = account.contacts.create!(name: 'Lead Primário Oculto', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: hidden_contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: agent,
      primary_conversation: hidden_conversation,
      title: 'Card visível sem conversa',
      metadata: {
        'source_conversation' => {
          'id' => hidden_conversation.id,
          'display_id' => hidden_conversation.display_id
        }
      }
    )

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload['conversation_id']).to be_nil
    expect(payload['conversation']).to be_nil
    expect(payload['linked_conversations']).to be_empty
    expect(payload['metadata']).not_to have_key('source_conversation')
  end

  it 'sanitizes hidden primary conversation data from card index for agents' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    hidden_contact = account.contacts.create!(name: 'Lead Lista Oculta', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: hidden_contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: agent,
      primary_conversation: hidden_conversation,
      title: 'Card na lista',
      metadata: {
        'source_conversation' => {
          'id' => hidden_conversation.id,
          'display_id' => hidden_conversation.display_id
        }
      }
    )

    get "/api/v1/accounts/#{account.id}/crm/cards",
        params: { pipeline_id: pipeline.id },
        headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload'].find { |card_payload| card_payload['id'] == card.id }
    expect(payload['conversation_id']).to be_nil
    expect(payload['conversation']).to be_nil
    expect(payload['metadata']).not_to have_key('source_conversation')
  end

  it 'prevents agents from creating cards in inboxes they cannot access' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: { pipeline_id: pipeline.id, stage_id: stage.id, inbox_id: inbox.id, title: 'Sem permissão' } },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.crm_cards.where(title: 'Sem permissão')).to be_blank
  end

  it 'ignores forged links when creating a card from an authorized conversation' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    allowed_inbox = create_crm_inbox(account: account, members: [agent])
    hidden_inbox = create_crm_inbox(account: account)
    contact = account.contacts.create!(name: 'Ana Lima', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: allowed_inbox, contact: contact, assignee: agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: {
           card: {
             pipeline_id: pipeline.id,
             stage_id: stage.id,
             conversation_id: conversation.id,
             inbox_id: hidden_inbox.id,
             owner_id: admin.id,
             title: 'Com conversa'
           }
         },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['conversation_id']).to eq(conversation.id)
    expect(payload['inbox_id']).to eq(allowed_inbox.id)
    expect(payload['owner_id']).to eq(agent.id)
  end

  it 'does not attach hidden conversations through the generic update endpoint' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    contact = account.contacts.create!(name: 'Oculto', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Card visível')

    patch "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}",
          params: { card: { conversation_id: hidden_conversation.id, title: 'Ainda visível' } },
          headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    card.reload
    expect(card.conversation_id).to be_nil
    expect(card.title).to eq('Ainda visível')
  end

  it 'authorizes the target conversation before unlinking it' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    contact = account.contacts.create!(name: 'Oculto', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Card visível')
    account.crm_card_conversations.create!(card: card, conversation: hidden_conversation, linked_by: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/unlink_conversation",
         params: { conversation_id: hidden_conversation.id },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.crm_card_conversations.where(card: card, conversation: hidden_conversation)).to exist
  end

  it 'blocks conversation-backed create in assigned-only inboxes when the conversation is assigned to another agent' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    other_agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent, other_agent])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead atribuído', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards",
         params: { card: { pipeline_id: pipeline.id, stage_id: stage.id, conversation_id: conversation.id, title: 'Não cria' } },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.crm_cards.where(title: 'Não cria')).to be_blank
    expect(account.crm_activities.where(event_type: 'create')).to be_blank
  end

  it 'blocks from_conversation in assigned-only inboxes before persisting the card' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    other_agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent, other_agent])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead de outro agente', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, created_by: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards/from_conversation",
         params: { conversation_id: conversation.id, pipeline_id: pipeline.id },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.crm_cards.where(conversation_id: conversation.id)).to be_blank
    expect(account.crm_activities.where(event_type: 'create')).to be_blank
  end

  it 'blocks linking assigned-only conversations that belong to another agent' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    other_agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent, other_agent])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead oculto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Card do agente')

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/link_conversation",
         params: { conversation_id: conversation.id, primary: true },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    card.reload
    expect(card.conversation_id).to be_nil
    expect(account.crm_card_conversations.where(card: card, conversation: conversation)).to be_blank
  end

  it 'blocks unlinking assigned-only conversations that belong to another agent' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    other_agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent, other_agent])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead oculto', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Card do agente')
    account.crm_card_conversations.create!(card: card, conversation: conversation, linked_by: admin)

    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/unlink_conversation",
         params: { conversation_id: conversation.id },
         headers: auth_headers(agent)

    expect(response).to have_http_status(:unauthorized)
    expect(account.crm_card_conversations.where(card: card, conversation: conversation)).to exist
  end

  it 'hides assigned-only cards from direct access and Kanban when assigned to another agent' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    other_agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent, other_agent])
    account.crm_inbox_settings.create!(inbox: inbox, visibility_mode: :assigned_only)
    contact = account.contacts.create!(name: 'Lead privado', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: other_agent)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      owner: other_agent,
      contact: contact,
      primary_conversation: conversation,
      title: 'Card privado'
    )

    get "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}", headers: auth_headers(agent)
    expect(response).to have_http_status(:not_found)

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: { pipeline_id: pipeline.id, limit_per_stage: 10 },
        headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    cards = response.parsed_body.dig('payload', 'stages').flat_map { |stage_payload| stage_payload['cards'] }
    expect(cards.pluck('id')).not_to include(card.id)
  end

  it 'includes linked conversation details in Kanban cards' do
    account, user = create_account_and_user
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead com conversa', phone_number: '+5511987654321')
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      inbox: inbox,
      contact: contact,
      primary_conversation: conversation,
      title: 'Lead com conversa'
    )

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: { pipeline_id: pipeline.id, limit_per_stage: 10 },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    cards = response.parsed_body.dig('payload', 'stages').flat_map { |stage_payload| stage_payload['cards'] }
    card_payload = cards.find { |payload| payload['id'] == card.id }
    expect(card_payload.dig('conversation', 'id')).to eq(conversation.id)
    expect(card_payload.dig('conversation', 'display_id')).to eq(conversation.display_id)
    expect(card_payload.dig('conversation', 'inbox_id')).to eq(inbox.id)
  end

  it 'sanitizes hidden primary conversation data from Kanban cards for agents' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    hidden_inbox = create_crm_inbox(account: account)
    hidden_contact = account.contacts.create!(name: 'Lead oculto no Kanban', phone_number: '+5511987654321')
    hidden_conversation = create_crm_conversation(account: account, inbox: hidden_inbox, contact: hidden_contact)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card = account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      owner: agent,
      primary_conversation: hidden_conversation,
      title: 'Card Kanban visível'
    )

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: { pipeline_id: pipeline.id, limit_per_stage: 10 },
        headers: auth_headers(agent)

    expect(response).to have_http_status(:ok)
    cards = response.parsed_body.dig('payload', 'stages').flat_map { |stage_payload| stage_payload['cards'] }
    card_payload = cards.find { |payload| payload['id'] == card.id }
    expect(card_payload['conversation_id']).to be_nil
    expect(card_payload['conversation']).to be_nil
  end

  it 'paginates cards per kanban stage instead of loading the full board' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    3.times { |index| account.crm_cards.create!(pipeline: pipeline, stage: stage, title: "Card #{index}") }

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: { pipeline_id: pipeline.id, limit_per_stage: 2 },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    stage_payload = response.parsed_body.dig('payload', 'stages').first
    expect(stage_payload['cards'].size).to eq(2)
    expect(stage_payload['cards_count']).to be_nil
    expect(stage_payload['has_more']).to be(true)
    expect(stage_payload['next_cursor']).to be_present
  end

  it 'loads more cards for only the requested kanban stage' do
    account, user = create_account_and_user
    pipeline, first_stage = create_crm_pipeline(account: account, user: user)
    second_stage = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    older_first_stage_card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Mais antigo')
    newer_first_stage_card = account.crm_cards.create!(pipeline: pipeline, stage: first_stage, title: 'Mais novo')
    other_stage_card = account.crm_cards.create!(pipeline: pipeline, stage: second_stage, title: 'Outra etapa')

    get "/api/v1/accounts/#{account.id}/crm/kanban",
        params: {
          pipeline_id: pipeline.id,
          limit_per_stage: 1,
          stage_ids: [first_stage.id],
          cursor_by_stage: { first_stage.id.to_s => newer_first_stage_card.id }
        },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    stages = response.parsed_body.dig('payload', 'stages')
    expect(stages.pluck('id')).to eq([first_stage.id])
    expect(stages.first['cards'].pluck('id')).to eq([older_first_stage_card.id])
    expect(stages.flat_map { |stage_payload| stage_payload['cards'] }.pluck('id')).not_to include(other_stage_card.id)
  end

  # Conta 16 (06/10/2026): o selo "Email Comercial · Novo" na lista de conversas passa a abrir o card no
  # CRM; para isso ele precisa do id do card, além de funil e etapa.
  it 'devolve o id do card no selo de etapa das conversas' do
    account, user = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    conversation = create(:conversation, account: account)
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', conversation_id: conversation.id)

    get "/api/v1/accounts/#{account.id}/crm/conversations/card_stages",
        params: { conversation_ids: [conversation.display_id] }, headers: auth_headers(user)

    expect(response.parsed_body.dig('payload', conversation.display_id.to_s)).to include('card_id' => card.id)
  end
end
