require 'rails_helper'

# #2277: "Novo público pedindo em palavras" by the API — who may use it, the account flag, each search belongs to
# the person who asked, and the steps the screen calls.
RSpec.describe 'Conversation audiences API (#2277)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account).tap { |conta| conta.enable_features!('campanhas_publico_por_conversa') } }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:path) { "/api/v1/accounts/#{account.id}/campaign_journey/conversation_audiences" }

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def with_role(permissions)
    create(:user, account: account, role: :agent).tap do |user|
      role = create(:custom_role, account: account, permissions: permissions)
      user.account_users.find_by(account: account).update!(custom_role: role)
    end
  end

  def search_of(user, **attributes)
    ConversationAudienceSearch.create!(account: account, user: user, request: 'quem cotou', period: '30d', **attributes)
  end

  it 'answers 404 with the account flag off' do
    account.disable_features!('campanhas_publico_por_conversa')

    get "#{path}/status", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'refuses an agent without role, and a role with campaign_manage but without conversation_view' do
    get "#{path}/status", headers: headers(create(:user, account: account, role: :agent))
    expect(response).to have_http_status(:unauthorized)

    get "#{path}/status", headers: headers(with_role(%w[campaign_manage]))
    expect(response).to have_http_status(:unauthorized)

    get "#{path}/status", headers: headers(with_role(%w[campaign_manage conversation_participating_manage conversation_unassigned_manage]))
    expect(response).to have_http_status(:unauthorized)
  end

  it 'lets a role with campaign_manage and conversation_manage in (manage implies view)' do
    get "#{path}/status", headers: headers(with_role(%w[campaign_manage conversation_manage]))

    expect(response).to have_http_status(:ok)
  end

  it 'answers 404 for a search of another account' do
    other = create(:account).tap { |conta| conta.enable_features!('campanhas_publico_por_conversa') }
    foreign = ConversationAudienceSearch.create!(account: other, user: admin, request: 'quem cotou', period: '30d', status: 'done')

    get "#{path}/#{foreign.id}", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'answers 404 on every step of a search of someone else' do
    search = search_of(with_role(%w[campaign_manage conversation_view]), status: 'done')
    person = ConversationAudiencePerson.create!(search: search, contact: create(:contact, account: account),
                                                conversation: create(:conversation, account: account), group: 'certeza')

    get "#{path}/#{search.id}/conversation", params: { person_id: person.id }, headers: headers
    expect(response).to have_http_status(:not_found)
    post "#{path}/#{search.id}/save", params: { name: 'X', person_ids: [person.id] }, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    %w[start stop resume answer].each do |step|
      post "#{path}/#{search.id}/#{step}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
    expect(account.campaign_imports).to be_empty
  end

  it 'says whether the account has its own AI key and how many conversations each period has' do
    inbox = create(:inbox, account: account)
    create(:conversation, account: account, inbox: inbox, last_activity_at: 2.days.ago)
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao')

    get "#{path}/status", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('has_own_key' => false, 'open_search_id' => nil)
    expect(response.parsed_body['periods']).to include('7d' => 1, 'all' => 1)
  end

  it 'starts planning the request and lets the screen follow it' do
    post path, params: { request: 'quem pediu cotação pra europa', period: '3m' }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    search = ConversationAudienceSearch.last
    expect(search).to have_attributes(user_id: admin.id, request: 'quem pediu cotação pra europa', period: '3m', status: 'planning')
    expect(ConversationAudience::PlanJob).to have_been_enqueued.with(search.id)

    get "#{path}/#{search.id}", headers: headers
    expect(response.parsed_body).to include('id' => search.id, 'status' => 'planning', 'people' => [])
  end

  it 'refuses a second request while one is still working on the account key' do
    search_of(admin, status: 'reading')

    post path, params: { request: 'outro pedido', period: '3m' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('search_in_progress')
  end

  it 'counts and shows only conversations of the inboxes a role limited to one inbox can open' do
    seen_inbox = create(:inbox, account: account)
    hidden_inbox = create(:inbox, account: account)
    user = with_role(%w[campaign_manage conversation_view])
    create(:inbox_member, user: user, inbox: seen_inbox)
    create(:conversation, account: account, inbox: seen_inbox)
    hidden = create(:conversation, account: account, inbox: hidden_inbox)
    create(:message, account: account, inbox: hidden_inbox, conversation: hidden, content: 'segredo da outra caixa')
    search = search_of(user, status: 'done')
    person = ConversationAudiencePerson.create!(search: search, contact: hidden.contact, conversation: hidden, group: 'certeza')

    get "#{path}/status", headers: headers(user)
    expect(response.parsed_body['periods']['all']).to eq(1)

    get "#{path}/#{search.id}/conversation", params: { person_id: person.id }, headers: headers(user)
    expect(response.parsed_body['payload']).to eq([])

    get "#{path}/#{search.id}", headers: headers(user)
    expect(response.parsed_body['people']).to eq([])

    post "#{path}/#{search.id}/save", params: { name: 'Vazou?', person_ids: [person.id] }, headers: headers(user), as: :json
    expect(response.parsed_body['error']).to eq('no_people')
  end

  it 'refuses an unknown period' do
    post path, params: { request: 'quem cotou', period: '2y' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'lets a role with campaign_manage and conversation_view use it, and never shows a search of someone else' do
    user = with_role(%w[campaign_manage conversation_view])

    get "#{path}/#{search_of(admin).id}", headers: headers(user)

    expect(response).to have_http_status(:not_found)
  end

  it 'takes the answer to the question once and plans again' do
    search = search_of(admin, status: 'question')

    2.times { post "#{path}/#{search.id}/answer", params: { answer: '3 ou mais' }, headers: headers, as: :json }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(search.reload).to have_attributes(answer: '3 ou mais', status: 'planning')
    expect(ConversationAudience::PlanJob).to have_been_enqueued.with(search.id).once
  end

  it 'does not resume a search with nothing left to read, and gives a lost search a new job' do
    failed = search_of(admin, status: 'failed', error: 'plan_error')
    post "#{path}/#{failed.id}/resume", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)

    lost = search_of(admin, status: 'reading', heartbeat_at: 1.hour.ago)
    get "#{path}/#{lost.id}", headers: headers
    expect(ConversationAudience::ReadJob).to have_been_enqueued.with(lost.id)
  end

  it 'starts a planned search, stops it and resumes it' do
    search = search_of(admin, status: 'planned', ceiling_usd: 0.5)
    ConversationAudienceBatch.create!(search: search, number: 1, conversation_ids: [1], chars: 10)

    post "#{path}/#{search.id}/start", headers: headers
    expect(search.reload.status).to eq('queued')
    expect(ConversationAudience::ReadJob).to have_been_enqueued.with(search.id)

    post "#{path}/#{search.id}/stop", headers: headers
    expect(search.reload.status).to eq('planned')

    post "#{path}/#{search.id}/start", headers: headers
    search.update!(status: 'reading', conversations_read: 20)
    post "#{path}/#{search.id}/stop", headers: headers
    expect(search.reload.status).to eq('stopped')

    post "#{path}/#{search.id}/resume", headers: headers
    expect(search.reload.status).to eq('queued')

    post "#{path}/#{search.id}/start", headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'shows the contact data of a saved audience only to who reads contacts' do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'time',
                                         attribute_display_name: 'Time', attribute_display_type: 'text')
    contact = create(:contact, account: account, name: 'João', phone_number: '+5511987654321',
                               custom_attributes: { 'time' => 'Cruzeiro' }, additional_attributes: { 'company_name' => 'João X' })
    search = search_of(admin, status: 'done')
    person = ConversationAudiencePerson.create!(search: search, contact: contact, group: 'certeza',
                                                conversation: create(:conversation, account: account, contact: contact))
    post "#{path}/#{search.id}/save", params: { name: 'Cruzeirenses', person_ids: [person.id] }, headers: headers, as: :json
    audience_path = "/api/v1/accounts/#{account.id}/campaign_imports/#{response.parsed_body['id']}"

    without = with_role(%w[campaign_manage])
    get "#{audience_path}/sample_contact", headers: headers(without)
    expect(response.parsed_body['payload']).to include('name' => 'João', 'company_name' => nil, 'extra_values' => {})
    get "#{audience_path}/contacts", headers: headers(without)
    expect(response.parsed_body['payload'].sole['company_name']).to be_nil

    get "#{audience_path}/sample_contact", headers: headers(with_role(%w[campaign_manage contact_view]))
    expect(response.parsed_body['payload']).to include('company_name' => 'João X', 'extra_values' => { 'Time' => 'Cruzeiro' })
  end

  it 'shows the people found without who cannot receive, and saves the audience' do
    search = search_of(admin, status: 'done')
    inbox = create(:inbox, account: account)
    mobile = create(:contact, account: account, name: 'Mariana', phone_number: '+5511987654321')
    landline = create(:contact, account: account, name: 'Fixo', phone_number: '+551133334444')
    kept, aside = [[mobile, nil], [landline, 'sem_contato']].map do |contact, left_aside|
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact)
      ConversationAudiencePerson.create!(search: search, contact: contact, conversation: conversation, group: 'certeza', reason: 'Cotou',
                                         left_aside: left_aside)
    end

    get "#{path}/#{search.id}", headers: headers
    expect(response.parsed_body['people'].pluck('id', 'name', 'confidence')).to eq([[kept.id, 'Mariana', 'certeza']])
    expect(response.parsed_body['left_aside']).to eq([%w[Fixo sem_contato]])

    post "#{path}/#{search.id}/save", params: { name: 'Cotaram', person_ids: [kept.id, aside.id] }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('name' => 'Cotaram', 'count' => 1)
    expect(account.campaign_imports.find(response.parsed_body['id'])).to be_audience
  end
end
