require 'rails_helper'

RSpec.describe 'Create a contact for an existing CRM card (M02)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: 'Existing opportunity', value_cents: 250_000)
  end
  let(:path) { "/api/v1/accounts/#{account.id}/crm/cards/#{card.id}/contact" }
  let(:headers) { auth_headers(admin).merge('Idempotency-Key' => SecureRandom.uuid) }
  let(:payload) { { contact: { name: 'Mariana Test', email: 'mariana-part2@example.com', phone_number: '+5531900000101' } } }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  it 'creates one shared contact on the same opportunity and preserves its commercial fields' do
    before = card.attributes.except('contact_id', 'last_activity_at', 'updated_at')
    counts = [Crm::Card.count, Conversation.count, ContactInbox.count, Message.count, Crm::FollowUp.count, ActionMailer::Base.deliveries.count]

    expect { post path, params: payload, headers: headers, as: :json }.to change(Contact, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['payload']).to include('id' => card.id, 'contact_id' => card.reload.contact_id)
    expect(card.attributes.except('contact_id', 'last_activity_at', 'updated_at')).to eq(before)
    expect(card.contact).to have_attributes(name: 'Mariana Test', email: 'mariana-part2@example.com', phone_number: '+5531900000101')
    expect(card.activities.last).to have_attributes(event_type: 'contact_linked', actor_id: admin.id)
    expect(
      [Crm::Card.count, Conversation.count, ContactInbox.count, Message.count, Crm::FollowUp.count, ActionMailer::Base.deliveries.count]
    ).to eq(counts)
  end

  it 'keeps a name-only contact visible and does not fabricate contact details or an external identifier' do
    post path, params: { contact: { name: 'Name Only CRM' } }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    created_contact = card.reload.contact
    expect(created_contact).to have_attributes(
      name: 'Name Only CRM', contact_type: 'lead', email: nil, phone_number: nil, identifier: nil
    )
    account.disable_features!('crm_v2')
    get "/api/v1/accounts/#{account.id}/contacts", headers: auth_headers(admin)
    expect(response.parsed_body['payload'].pluck('id')).to include(created_contact.id)
    account.enable_features!('crm_v2')
    get "/api/v1/accounts/#{account.id}/contacts", headers: auth_headers(admin)
    expect(response.parsed_body['payload'].pluck('id')).to include(created_contact.id)
    get "/api/v1/accounts/#{account.id}/contacts/search", params: { q: 'Name Only CRM' }, headers: auth_headers(admin)
    expect(response.parsed_body['payload'].pluck('id')).to include(created_contact.id)
  end

  it 'preserves name-only contacts after unlinking and after the visitor cleanup age' do
    post path, params: { contact: { name: 'Registered relationship' } }, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    person = card.reload.contact
    person.update!(created_at: 40.days.ago)
    Crm::Cards::ContactLinker.new(card: card, contact: person, actor: admin).unlink

    expect { Internal::RemoveStaleContactsService.new(account: account).perform }.not_to change(Contact, :count)
    expect(account.contacts.resolved_contacts(use_crm_v2: false)).to include(person)
  end

  it 'stores supported additional and custom values on the real contact' do
    values = { name: ' Person ', email: ' New-Part2@Example.com ', additional_attributes: { city: 'Curitiba', country: 'BR' },
               custom_attributes: { job_title: 'Director', address: 'Test street', test_interest: 'CRM' } }
    post path, params: { contact: values }, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(card.reload.contact).to have_attributes(name: 'Person', email: 'new-part2@example.com')
    expect(card.contact.additional_attributes).to include('city' => 'Curitiba', 'country' => 'BR')
    expect(card.contact.custom_attributes).to include('job_title' => 'Director', 'address' => 'Test street', 'test_interest' => 'CRM')
  end

  it 'replays a successful request without creating a second contact or activity' do
    post path, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    original = response.parsed_body
    counts = [Contact.count, Crm::Card.count, Crm::Activity.count]

    post path, params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(response.parsed_body).to eq(original)
    expect([Contact.count, Crm::Card.count, Crm::Activity.count]).to eq(counts)
  end

  it 'rejects reuse of the key for a different request without replacing the person' do
    post path, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    contact_id = card.reload.contact_id

    expect do
      post path, params: { contact: { name: 'Someone else' } }, headers: headers, as: :json
    end.not_to change(Contact, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.dig('error', 'code')).to eq('crm.idempotency.key_reuse')
    expect(card.reload.contact_id).to eq(contact_id)
  end

  it 'requires the idempotency key for this new operation' do
    card
    expect { post path, params: payload, headers: auth_headers(admin), as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  [nil, '', '  ', 12, [], {}].each do |invalid_name|
    it "rejects an invalid name #{invalid_name.inspect} without leaving a contact or idempotency record" do
      card
      counts = [Contact.count, IdempotencyKey.count]
      post path, params: { contact: { name: invalid_name } }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect([Contact.count, IdempotencyKey.count]).to eq(counts)
      expect(card.reload.contact_id).to be_nil
    end
  end

  [nil, 'invalid', [], 123].each do |invalid_contact|
    it "rejects a non-object contact #{invalid_contact.inspect} with 422, not 500" do
      card
      expect { post path, params: { contact: invalid_contact }, headers: headers, as: :json }.not_to change(Contact, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  [{ email: [] }, { phone_number: 123 }, { additional_attributes: 'bad' }, { custom_attributes: [] },
   { additional_attributes: { city: {} } }, { account_id: 1 }, { company_id: 1 }, { identifier: 'forged' }].each do |invalid_values|
    it "rejects unsupported types or identity fields #{invalid_values.inspect}" do
      card
      post path, params: { contact: payload[:contact].merge(invalid_values) }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(card.reload.contact_id).to be_nil
    end
  end

  [{ email: 'not-an-email' }, { phone_number: '5531invalid' }].each do |invalid_values|
    it "uses the existing contact validations for #{invalid_values.inspect}" do
      card
      counts = [Contact.count, Crm::Activity.count, IdempotencyKey.count]
      post path, params: { contact: payload[:contact].merge(invalid_values) }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect([Contact.count, Crm::Activity.count, IdempotencyKey.count]).to eq(counts)
    end
  end

  it 'refuses an already linked card even when a different request key is supplied' do
    existing = account.contacts.create!(name: 'Existing', email: 'existing@example.com')
    card.update!(contact: existing)
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(card.reload.contact_id).to eq(existing.id)
  end

  it 'rolls back the new contact if a legacy primary conversation belongs to someone else' do
    original = account.contacts.create!(name: 'Private original', email: 'private-original@example.com')
    inbox = create_crm_inbox(account: account, members: [admin])
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: original)
    card.update!(primary_conversation: conversation)
    counts = [Contact.count, IdempotencyKey.count, Crm::Activity.count]

    post path, params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).not_to include(original.email, original.name)
    expect([Contact.count, IdempotencyKey.count, Crm::Activity.count]).to eq(counts)
    expect(card.reload.contact_id).to be_nil
    expect(conversation.reload.contact_id).to eq(original.id)
  end

  it 'rolls back the new contact if a secondary conversation belongs to someone else' do
    original = account.contacts.create!(name: 'Original', email: 'secondary-original@example.com')
    inbox = create_crm_inbox(account: account, members: [admin])
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: original)
    card.card_conversations.create!(account: account, conversation: conversation, linked_by: admin)
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(card.reload.contact_id).to be_nil
  end

  it 'rejects duplicate email without merging or overwriting the existing contact' do
    original = account.contacts.create!(name: 'Original', email: payload[:contact][:email])
    card
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(original.reload.name).to eq('Original')
    expect(card.reload.contact_id).to be_nil
  end

  it 'rejects duplicate phone without overwriting the existing contact' do
    original = account.contacts.create!(name: 'Original phone', phone_number: payload[:contact][:phone_number])
    card
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(original.reload.name).to eq('Original phone')
    expect(card.reload.contact_id).to be_nil
  end

  it 'does not bypass contact creation authorization' do
    card
    allow(ContactPolicy).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |policy| allow(policy).to receive(:create?).and_return(false) }
    end
    expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires authentication and does not allow replay by an unauthenticated request' do
    post path, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    post path, params: payload, headers: { 'Idempotency-Key' => headers['Idempotency-Key'] }, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects a card that belongs to another account' do
    other_account = create(:account)
    outsider = create(:user, account: other_account, role: :administrator)
    card
    expect do
      post path, params: payload, headers: auth_headers(outsider).merge('Idempotency-Key' => SecureRandom.uuid), as: :json
    end.not_to change(Contact, :count)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'preserves the disabled-CRM gate' do
    card
    with_modified_env('CRM_KANBAN_ENABLED' => 'false') do
      expect { post path, params: payload, headers: headers, as: :json }.not_to change(Contact, :count)
      expect(response).to have_http_status(:not_found)
    end
  end
end
