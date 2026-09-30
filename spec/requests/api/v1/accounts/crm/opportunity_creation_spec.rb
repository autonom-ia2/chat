require 'rails_helper'

RSpec.describe 'CRM opportunity creation from shared relationships', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:contact) { account.contacts.create!(name: 'Existing person', email: 'person@example.com', custom_attributes: { 'keep' => 0 }) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/cards" }
  let(:key) { SecureRandom.uuid }
  let(:headers) { auth_headers(admin).merge('Idempotency-Key' => key) }
  let(:payload) do
    { card: { title: 'Manual opportunity', pipeline_id: pipeline_and_stage.first.id, stage_id: pipeline_and_stage.last.id,
              contact_id: contact.id, value_cents: 120_045, currency: 'BRL', priority: 'urgent', score: 0 } }
  end

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  it 'creates only the opportunity and keeps the shared contact unchanged' do
    payload
    before = contact.attributes
    expect { post url, params: payload, headers: headers, as: :json }
      .to change(Crm::Card, :count).by(1).and not_change(Contact, :count).and not_change(Message, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('payload')).to include('contact_id' => contact.id, 'value_cents' => 120_045, 'priority' => 'urgent')
    expect(contact.reload.attributes).to eq(before)
  end

  it 'creates an unlinked opportunity without inventing a person or channel' do
    payload[:card].delete(:contact_id)
    expect { post url, params: payload, headers: headers, as: :json }
      .to change(Crm::Card, :count).by(1).and not_change(Contact, :count).and not_change(Conversation, :count)
    expect(response).to have_http_status(:created)
    expect(response.parsed_body.fetch('payload')).to include('contact_id' => nil, 'conversation_id' => nil)
  end

  it 'replays the confirmed opportunity without another card or activity' do
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body.dig('payload', 'id')
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Crm::Card, :count).and not_change(Crm::Activity, :count)
    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(response.parsed_body.dig('payload', 'id')).to eq(id)
  end

  it 'rejects a key reused with different content without changing the original opportunity' do
    post url, params: payload, headers: headers, as: :json
    payload[:card][:title] = 'Different intention'
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.crm_cards.last.title).to eq('Manual opportunity')
  end

  it 'does not strand a processing key after validation fails' do
    payload[:card][:title] = ''
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:unprocessable_entity)
    payload[:card][:title] = 'Corrected title'
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
  end

  it 'rolls back the opportunity and key if capturing the response fails, then permits a retry' do
    payload
    allow(IdempotencyKey).to receive(:find).and_wrap_original do |original, *args|
      original.call(*args).tap do |record|
        allow(record).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(record))
      end
    end
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count).and not_change(Crm::Activity, :count)
    allow(IdempotencyKey).to receive(:find).and_call_original
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:created)
    expect(account.crm_cards.count).to eq(1)
  end

  it 'revalidates visibility rather than returning a stale payload after the card is deleted' do
    post url, params: payload, headers: headers, as: :json
    account.crm_cards.find(response.parsed_body.dig('payload', 'id')).destroy!
    post url, params: payload, headers: headers, as: :json
    expect(response).to have_http_status(:not_found)
    expect(account.crm_cards.count).to eq(0)
  end

  it 'does not attach a contact from another account' do
    payload[:card][:contact_id] = create(:contact).id
    expect { post url, params: payload, headers: headers, as: :json }
      .to not_change(Crm::Card, :count).and not_change(IdempotencyKey, :count)
    expect(response).to have_http_status(:not_found)
  end

  it 'does not accept a stage from a different pipeline' do
    other_pipeline = create_crm_pipeline(account: account, user: admin)
    payload[:card][:stage_id] = other_pipeline.last.id
    expect { post url, params: payload, headers: headers, as: :json }.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'preserves external upsert behavior with independent request keys' do
    payload[:card][:external_id] = 'qa-existing-external-reference'
    post url, params: payload, headers: headers, as: :json
    id = response.parsed_body.dig('payload', 'id')
    payload[:card][:title] = 'External update'
    next_headers = headers.merge('Idempotency-Key' => SecureRandom.uuid)
    expect { post url, params: payload, headers: next_headers, as: :json }.not_to change(Crm::Card, :count)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to include('id' => id, 'title' => 'External update')
    post url, params: payload, headers: next_headers, as: :json
    expect(response.headers['Idempotency-Replayed']).to eq('true')
    expect(response.parsed_body.dig('payload', 'id')).to eq(id)
  end

  it 'does not replay a confirmed response for an unauthenticated request' do
    post url, params: payload, headers: headers, as: :json
    post url, params: payload, headers: { 'Idempotency-Key' => key }, as: :json
    expect(response).to have_http_status(:unauthorized)
    expect(response.body).not_to include('Manual opportunity')
  end

  it 'keeps the existing unkeyed API contract working' do
    post url, params: payload, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    expect(response.headers['Idempotency-Replayed']).to be_nil
  end
end
