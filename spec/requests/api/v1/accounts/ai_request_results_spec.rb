require 'rails_helper'

RSpec.describe 'Interactive AI result contracts', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:headers) { user.create_new_auth_token }
  let(:channel) { create(:channel_email, account: account, calendar_enabled: true) }
  let(:inbox) { channel.inbox }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, title: 'Teste',
                              contact: create(:contact, account: account, email: 'test@example.com'))
  end
  let(:meeting) do
    account.crm_meetings.create!(card: card, inbox: inbox, created_by: user, title: 'Teste', provider: :google,
                                 starts_at: 1.day.from_now, ends_at: 1.day.from_now + 30.minutes)
  end
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Teste', agent_type: 'custom', mode: :guided,
                                     instruction: 'Ajude', status: :active, enabled: true)
  end

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', CRM_KANBAN_ENABLED: 'true',
                      CRM_CALENDAR_MEETINGS_ENABLED: 'true', CRM_AI_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true' do
      example.run
    end
  end

  [[:draft_invite, 'Crm::Ai::DraftInviteService', { description: 'Convite', ai_available: true }],
   [:summarize, 'Crm::Ai::MeetingSummaryService', { summary: 'Resumo', ai_available: true }]].each do |action, service_name, result|
    it "keeps the meeting #{action} payload after asynchronous execution" do
      service_class = service_name.constantize
      service = instance_double(service_class, perform: result)
      allow(service_class).to receive(:new).and_return(service)
      suffix = action == :summarize ? "#{meeting.id}/summarize" : 'draft_invite'
      post "/api/v1/accounts/#{account.id}/crm/meetings/#{suffix}",
           params: { card_id: card.id, title: 'Teste' }, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      request = response.parsed_body
      expect(service).not_to have_received(:perform)
      Crm::Ai::InteractiveJob.perform_now(request['id'])
      get request['poll_url'], headers: headers
      expect(response.parsed_body).to include('status' => 'done', 'result' => result.stringify_keys)
    end
  end

  it 'preserves time suggestions and the selected user and inbox' do
    suggestions = [{ starts_at: '2026-10-01T09:00:00-03:00', reason: 'Livre' }]
    service = instance_double(Crm::Ai::SuggestMeetingTimeService, perform: suggestions)
    allow(Crm::Ai::SuggestMeetingTimeService).to receive(:new).and_return(service)
    post "/api/v1/accounts/#{account.id}/crm/meetings/suggest_times",
         params: { card_id: card.id, inbox_id: inbox.id, date: '2026-10-01' }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body['result']['suggestions']).to eq(suggestions.map(&:stringify_keys))
    expect(Crm::Ai::SuggestMeetingTimeService).to have_received(:new).with(hash_including(agent: user, inbox: inbox, card: card))
  end

  it 'preserves the card summary envelope' do
    result = Crm::Ai::ConversationSummarizer::Result.new(status: :generated, text: 'Resumo', generated_at: Time.current)
    allow(Crm::Ai::ConversationSummarizer).to receive(:new)
      .and_return(instance_double(Crm::Ai::ConversationSummarizer, perform: result))
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/summarize", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body['result']['payload']).to include('status' => 'generated', 'ai_summary' => hash_including('text' => 'Resumo'))
  end

  it 'preserves the card evaluation envelope' do
    result = Crm::Ai::Evaluator::Result.new(status: :skipped, suggestion: nil)
    allow(Crm::Ai::Evaluator).to receive(:new).and_return(instance_double(Crm::Ai::Evaluator, perform: result))
    post "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/evaluate_ai", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body['result']).to eq('payload' => { 'status' => 'skipped', 'suggestion' => nil })
  end

  it 'rewrites email text asynchronously using the same structured response' do
    resolver = instance_double(Crm::Ai::CredentialResolver, resolve: { api_key: 'test' })
    client = instance_double(Crm::Ai::ResponsesClient, create: { text: '{"text":"Novo texto"}' })
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(resolver)
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client)
    post "/api/v1/accounts/#{account.id}/email_campaigns/ai/rewrite",
         params: { text: 'Original', instruction: 'Encurte' }, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    request = response.parsed_body
    expect(client).not_to have_received(:create)
    Crm::Ai::InteractiveJob.perform_now(request['id'])
    get request['poll_url'], headers: headers
    expect(response.parsed_body).to include('status' => 'done', 'result' => { 'text' => 'Novo texto' })
  end

  %w[test suggest].each do |action|
    it "preserves the agent #{action} view without exposing raw instructions" do
      result = Autonomia::Agents::AnswerResult.new(reply: 'Resposta', confidence: 0.9, handoff: { should: false, reason: nil })
      allow(Autonomia::Agents::Answerer).to receive(:new).and_return(instance_double(Autonomia::Agents::Answerer, answer: result))
      post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/#{action}",
           params: { message: 'Oi', history: [{ role: 'user', content: 'Antes' }] }, headers: headers, as: :json
      expect(response).to have_http_status(:accepted)
      request = response.parsed_body
      Crm::Ai::InteractiveJob.perform_now(request['id'])
      get request['poll_url'], headers: headers
      expect(response.parsed_body['status']).to eq('done')
      expect(Autonomia::Agents::Answerer).to have_received(:new).with(hash_including(history: [{ role: 'user', content: 'Antes' }]))
      expect(response.parsed_body['result']).to include('reply' => 'Resposta', 'handoff' => { 'should' => false, 'reason' => nil })
      expect(response.parsed_body['result']).not_to have_key('instruction')
    end
  end
end
