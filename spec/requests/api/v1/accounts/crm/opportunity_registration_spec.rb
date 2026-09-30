require 'rails_helper'

RSpec.describe 'CRM composed opportunity registration', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:headers) { admin.create_new_auth_token.merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/cards" }
  let(:payload) do
    { card: { title: 'Registered opportunity', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
              relationship: { mode: 'new', contact: { name: 'New person' }, company: { mode: 'none' } } } }
  end

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    payload
    headers
  end

  it 'creates a name-only lead and opportunity without conversations or messages' do
    expect { post url, params: payload, headers: headers, as: :json }
      .to change(Contact, :count).by(1).and change(Crm::Card, :count).by(1)
      .and not_change(Conversation, :count).and not_change(Message, :count)
    expect(response).to have_http_status(:created)
    card = account.crm_cards.find(response.parsed_body.dig('payload', 'id'))
    expect(card.contact).to have_attributes(name: 'New person', email: nil, phone_number: nil, contact_type: 'lead')
    expect(account.contacts.resolved_contacts).to include(card.contact)
    card.contact.update!(created_at: 2.years.ago)
    expect(Contact.stale_without_conversations(1.year.ago)).not_to include(card.contact)
  end

  it 'replays the same entire registration without recreating either entity' do
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body.dig('payload', 'id')
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Contact, :count).and not_change(Crm::Card, :count)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(response.parsed_body.dig('payload', 'id')).to eq(id)
  end

  it 'reverts the new contact and idempotency key when the opportunity is invalid, then permits correction' do
    payload[:card][:title] = ''
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'section')).to eq('opportunity')
    payload[:card][:title] = 'Corrected'
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  it 'returns the existing contact without overwriting it for a normalized duplicate email' do
    existing = create(:contact, account: account, name: 'Original', email: 'registered@example.com')
    before = existing.reload.attributes
    payload[:card][:relationship][:contact][:email] = '  REGISTERED@EXAMPLE.COM  '
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Contact, :count).and not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.opportunity.contact_exists')
    expect(response.parsed_body.dig('error', 'matches').pluck('id')).to eq([existing.id])
    expect(existing.reload.attributes).to eq(before)
  end

  it 'identifies a phone duplicate without merging or updating it' do
    existing = create(:contact, account: account, phone_number: '+14155552671')
    payload[:card][:relationship][:contact][:phone_number] = '+1 (415) 555-2671'
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'matches').pluck('id')).to eq([existing.id])
  end

  it 'requires an explicit decision when email and phone belong to different people' do
    email = create(:contact, account: account, email: 'email-owner@example.com')
    phone = create(:contact, account: account, phone_number: '+14155552671')
    payload[:card][:relationship][:contact].merge!(email: email.email, phone_number: phone.phone_number)
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.opportunity.identity_conflict')
    expect(response.parsed_body.dig('error', 'matches').pluck('id')).to contain_exactly(email.id, phone.id)
  end

  it 'does not consider a same-name person a duplicate' do
    create(:contact, account: account, name: 'New person')
    expect { post url, params: payload, headers: headers, as: :json }.to change(Contact, :count).by(1)
    expect(response).to have_http_status(:created)
  end

  it 'does not expose or reuse another account contact' do
    other = create(:contact, email: 'separate@example.com')
    payload[:card][:relationship][:contact][:email] = other.email
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.dig('payload', 'contact_id')).not_to eq(other.id)
  end

  it 'returns no identifying data for a matching contact that the current policy hides' do
    existing = create(:contact, account: account, email: 'hidden@example.com')
    payload[:card][:relationship][:contact][:email] = existing.email
    allow(Pundit).to receive(:policy!).and_call_original
    allow(Pundit).to receive(:policy!).with(anything, existing).and_return(instance_double(ContactPolicy, show?: false))
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body.dig('error', 'matches')).to eq([])
  end

  it 'validates the native optional contact fields without leaving partial records' do
    payload[:card][:relationship][:contact].merge!(email: 'not-an-email', phone_number: 'local-number')
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Contact, :count).and not_change(Crm::Card, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'fields').keys).to include('email', 'phone_number')
  end

  it 'preserves zero, false and canonical date attributes using the shared definitions' do
    account.enable_features!('custom_attributes')
    %w[number checkbox date].zip(%w[budget allowed date]).each do |type, key|
      create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_display_type: type, attribute_key: key)
    end
    values = { budget: 0, allowed: false, date: '2026-10-15', address: 'Test address', job_title: 'Buyer' }
    payload[:card][:relationship][:contact][:custom_attributes] = values
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(account.contacts.last.custom_attributes).to eq(values.stringify_keys)
  end

  it 'rejects invalid attribute values with their exact key, without saving a partial contact' do
    account.enable_features!('custom_attributes')
    create(:custom_attribute_definition, account: account, attribute_model: :contact_attribute, attribute_display_type: :number,
                                         attribute_key: 'budget')
    payload[:card][:relationship][:contact][:custom_attributes] = { budget: 'not-a-number' }
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'fields')).to have_key('custom_attributes.budget')
    expect(account.contacts.count).to eq(0)
  end

  it 'requires an idempotency header for a composed registration' do
    post url, params: payload, headers: headers.except('Idempotency-Key'), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.contacts.count).to eq(0)
  end

  %i[contact_id conversation_id external_id].each do |key|
    it "rejects a composed payload mixed with legacy #{key}" do
      payload[:card][key] = 123
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.contacts.count).to eq(0)
    end
  end

  [nil, '', [], { mode: 'other' }, { mode: 'new', contact: { name: [] } },
   { mode: 'new', contact: { name: 'Person', account_id: 99 } },
   { mode: 'new', contact: { name: 'Person', custom_attributes: [] } }].each do |input|
    it "rejects malformed registration input #{input.inspect}" do
      payload[:card][:relationship] = input
      post url, params: payload, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(account.contacts.count).to eq(0)
    end
  end

  it 'serializes registrations without upgrading the account foreign-key lock to FOR UPDATE' do
    statements = []
    subscriber = ->(*event) { statements << event.last[:sql] }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      post url, params: payload, headers: headers, as: :json
    end
    expect(response).to have_http_status(:created)
    account_locks = statements.select { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR ') }
    expect(account_locks.any? { |sql| sql.include?('FOR NO KEY UPDATE') }).to be(true)
    expect(account_locks.any? { |sql| sql.include?('FOR UPDATE') }).to be(false)
  end
end
