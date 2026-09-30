require 'rails_helper'

RSpec.describe 'CRM composed company registration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:headers) { admin.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/cards" }
  let(:payload) do
    { card: { title: 'Full registration', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
              relationship: { mode: 'new', contact: { name: 'New person', email: 'person@business.example' },
                              company: { mode: 'new', attributes: { name: 'Alameda', domain: 'https://ALAMEDA.example/about',
                                                                    additional_attributes: { city: 'Belo Horizonte' } } } } } }
  end

  before do
    account.enable_features!('companies', 'custom_attributes')
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    payload
    headers
  end

  it 'confirms one company, one lead and one opportunity with canonical associations' do
    expect { post url, params: payload, headers: headers, as: :json }
      .to change(Company, :count).by(1).and change(Contact, :count).by(1).and change(Crm::Card, :count).by(1)
      .and not_change(Conversation, :count).and not_change(Message, :count)
    expect(response).to have_http_status(:created)
    card = account.crm_cards.find(response.parsed_body.dig('payload', 'id'))
    expect(card.contact.company).to have_attributes(name: 'Alameda', domain: 'alameda.example', contacts_count: 1,
                                                    additional_attributes: { 'city' => 'Belo Horizonte' })
    expect(card.contact.additional_attributes).to include('company_name' => 'Alameda')
  end

  it 'replays the whole confirmed registration with no repeated company, person or opportunity' do
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body.dig('payload', 'id')
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Company, :count).and not_change(Contact, :count).and not_change(Crm::Card, :count)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(response.parsed_body.dig('payload', 'id')).to eq(id)
  end

  it 'links an existing company without overwriting its fields or another contact' do
    existing = create(:company, account: account, name: 'Existing', domain: 'existing.example', custom_attributes: { 'keep' => false })
    original = create(:contact, account: account, company: existing, name: 'Original')
    snapshot = original.reload.attributes
    payload[:card][:relationship][:company] = { mode: 'existing', id: existing.id }
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Company, :count)
    expect(response).to have_http_status(:created)
    expect(account.contacts.last.company_id).to eq(existing.id)
    expect(existing.reload).to have_attributes(name: 'Existing', custom_attributes: { 'keep' => false }, contacts_count: 2)
    expect(original.reload.attributes).to eq(snapshot)
  end

  it 'does not infer or create a company from email when the user selects no company' do
    payload[:card][:relationship][:company] = { mode: 'none' }
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Company, :count)
    expect(response).to have_http_status(:created)
    expect(account.contacts.last.company_id).to be_nil
  end

  it 'preserves native inference for unrelated contact registrations' do
    expect { account.contacts.create!(name: 'Native contact', email: 'native@unrelatedbusiness.example') }.to change(Company, :count).by(1)
    expect(account.contacts.last.company.domain).to eq('unrelatedbusiness.example')
  end

  it 'supports a named company without a domain and does not invent one from the contact email' do
    payload[:card][:relationship][:company][:attributes].delete(:domain)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(account.companies.last.domain).to be_nil
  end

  it 'permits two different companies with the same name' do
    original = create(:company, account: account, name: 'Alameda', domain: 'another.example')
    expect { post url, params: payload, headers: headers, as: :json }.to change(Company, :count).by(1)
    expect(response).to have_http_status(:created)
    expect(account.contacts.last.company_id).not_to eq(original.id)
  end

  it 'offers an existing same-domain company and rolls back the whole intent' do
    existing = create(:company, account: account, name: 'Original', domain: 'alameda.example')
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Company, :count).and not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.opportunity.company_exists')
    expect(response.parsed_body.dig('error', 'matches').pluck('id')).to eq([existing.id])
  end

  it 'rejects a company from another account without leaving a new person or key' do
    other = create(:company)
    payload[:card][:relationship][:company] = { mode: 'existing', id: other.id }
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Contact, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other.name)
  end

  it 'rolls back the new company when the contact is invalid' do
    payload[:card][:relationship][:contact][:email] = 'invalid'
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Company, :count).and not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'section')).to eq('contact')
  end

  it 'rolls back new company and contact when the opportunity is invalid' do
    payload[:card][:title] = ''
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Company, :count).and not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'section')).to eq('opportunity')
  end

  it 'rolls back everything when capturing the idempotent response fails' do
    allow(IdempotencyKey).to receive(:find).and_wrap_original do |original, *args|
      original.call(*args).tap { |record| allow(record).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(record)) }
    end
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Company, :count).and not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    allow(IdempotencyKey).to receive(:find).and_call_original
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  it 'preserves typed company attributes without copying them to the contact' do
    create(:custom_attribute_definition, account: account, attribute_model: :company_attribute, attribute_display_type: :checkbox,
                                         attribute_key: 'active')
    payload[:card][:relationship][:company][:attributes][:custom_attributes] = { active: false }
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(account.companies.last.custom_attributes).to eq('active' => false)
    expect(account.contacts.last.custom_attributes).to eq({})
  end

  it 'rejects company work when the feature is disabled instead of silently dropping it' do
    account.disable_features!('companies')
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(account.contacts.count).to eq(0)
  end

  it 'still permits no-company registration when Companies is disabled' do
    account.disable_features!('companies')
    payload[:card][:relationship][:company] = { mode: 'none' }
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  ['bad host', 'ftp://files.example', 'https://name:password@private.example', 'https://'].each do |domain|
    it "rejects invalid domain #{domain.inspect}" do
      payload[:card][:relationship][:company][:attributes][:domain] = domain
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body.dig('error', 'fields')).to have_key('domain')
      expect(account.contacts.count).to eq(0)
    end
  end

  [{ mode: 'existing', id: '1' }, { mode: 'none', id: 1 }, { mode: 'new', attributes: { name: '' } },
   { mode: 'new', attributes: { name: 'Company', additional_attributes: { city: [] } } }].each do |input|
    it "rejects malformed company input #{input.inspect}" do
      payload[:card][:relationship][:company] = input
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.contacts.count).to eq(0)
    end
  end

  it 'does not grant contact/company creation to a CRM-only integration token' do
    token = Crm::IntegrationToken.create!(account: account, name: 'Local composed scope test', scopes: ['crm_admin'], created_by: admin)
    expect do
      post url, params: payload, headers: { 'api_access_token' => token.access_token.token, 'Idempotency-Key' => SecureRandom.uuid }, as: :json
    end.to not_change(Contact, :count).and not_change(Company, :count).and not_change(Crm::Card, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'checks current CRM permissions before replaying a completed composite registration' do
    agent, membership = create_crm_agent(account: account)
    role = create(:custom_role, account: account, permissions: %w[crm_view crm_manage_cards])
    membership.update!(custom_role: role)
    agent_headers = auth_headers(agent).merge('Idempotency-Key' => SecureRandom.uuid)
    post url, params: payload, headers: agent_headers, as: :json
    expect(response).to have_http_status(:created)
    role.update!(permissions: ['crm_view'])
    post url, params: payload, headers: agent_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('New person')
    expect(response.headers['Idempotency-Replayed']).to be_nil
  end

  it 'does not emit committed creation events when the opportunity is rolled back' do
    allow(Crm::Webhooks::Emitter).to receive(:emit)
    dispatcher = Rails.configuration.dispatcher
    allow(dispatcher).to receive(:dispatch).and_call_original
    payload[:card][:title] = ''
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(Crm::Webhooks::Emitter).not_to have_received(:emit)
    expect(dispatcher).not_to have_received(:dispatch).with('contact.created', anything, anything)
  end
end
