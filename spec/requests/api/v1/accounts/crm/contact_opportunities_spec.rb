require 'rails_helper'

RSpec.describe 'CRM opportunities in the shared contact profile', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { account.contacts.create!(name: 'Person', email: 'person@example.com') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:attributes) { { pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact, owner: admin, title: 'Negotiation' } }
  let(:card) { account.crm_cards.create!(attributes.merge(value_cents: 125_050, currency: 'BRL')) }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/contacts/#{contact.id}/opportunities" }
  let(:headers) { auth_headers(admin) }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { example.run }
  end

  it 'returns only the minimal commercial projection with the real IDs and no writes' do
    card
    snapshot = contact.reload.attributes
    expect { get url, headers: headers }.to not_change(Crm::Card, :count).and not_change(Contact, :count)
      .and not_change(Message, :count).and not_change(Crm::Activity, :count)
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('payload').first
    expect(row.keys).to match_array(%w[id title status value_cents currency expected_close_at pipeline stage owner])
    expect(row).to include('id' => card.id, 'value_cents' => 125_050, 'currency' => 'BRL')
    expect(row['pipeline']).to eq('id' => card.pipeline_id, 'name' => card.pipeline.name)
    expect(row['owner']).to eq('id' => admin.id, 'name' => admin.name)
    expect(contact.reload.attributes).to eq(snapshot)
  end

  it 'uses canonical contact IDs, not names, company associations or conversation participants' do
    card
    other = account.contacts.create!(name: contact.name)
    account.crm_cards.create!(attributes.merge(contact: other, title: 'Other person'))
    get url, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([card.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
  end

  it 'collects all pipelines but excludes archived cards by default, not won/lost opportunities' do
    card
    other_pipeline = create_crm_pipeline(account: account, user: admin, name: 'Renewals')
    won = account.crm_cards.create!(attributes.merge(pipeline: other_pipeline.first, stage: other_pipeline.last, status: :won))
    lost = account.crm_cards.create!(attributes.merge(status: :lost))
    account.crm_cards.create!(attributes.merge(status: :archived))
    get url, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(card.id, won.id, lost.id)
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(3)
  end

  %w[open won lost archived].each do |status|
    it "filters #{status} without changing the records" do
      %w[open won lost archived].each { |value| account.crm_cards.create!(attributes.merge(status: value)) }
      get url, params: { result: status }, headers: headers
      expect(response.parsed_body['payload'].pluck('status')).to eq([status])
      expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    end
  end

  it 'includes archived records only when all or archived is requested' do
    %w[open won lost archived].each { |value| account.crm_cards.create!(attributes.merge(status: value)) }
    get url, params: { result: 'all' }, headers: headers
    expect(response.parsed_body['payload'].pluck('status')).to match_array(%w[open won lost archived])
  end

  it 'paginates deterministically, including equal timestamps, and bounds each response to five cards' do
    cards = Array.new(7) { account.crm_cards.create!(attributes.merge(updated_at: Time.utc(2026, 9, 30))) }
    get url, params: { per_page: 1000 }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq(cards.last(5).reverse.map(&:id))
    expect(response.parsed_body['meta']).to include('page' => 1, 'per_page' => 5, 'has_more' => true, 'total_count' => 7)
    get url, params: { page: 2 }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq(cards.reverse.last(2).map(&:id))
    expect(response.parsed_body.dig('meta', 'has_more')).to be(false)
  end

  it 'searches case-insensitively on the server and escapes SQL wildcard characters' do
    match = account.crm_cards.create!(attributes.merge(title: 'Renovação 50%_VIP'))
    account.crm_cards.create!(attributes.merge(title: 'Renovação 500 VIP'))
    get url, params: { search: '  50%_vip  ' }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([match.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
  end

  it 'keeps a valid empty result separate from a failed or unauthorized request' do
    get url, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('payload' => [], 'meta' => { 'total_count' => 0, 'page' => 1, 'per_page' => 5, 'has_more' => false })
  end

  [{ page: '0' }, { page: '-1' }, { page: '1x' }, { page: ['1'] }, { search: ['x'] },
   { result: ['all'] }, { result: 'unknown' }, { search: 'x' * 201 }].each do |input|
    it "rejects invalid input #{input.keys.inspect} #{input.values.first.class}" do
      card
      get url, params: input, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).not_to have_key('payload')
    end
  end

  it 'rejects a malformed contact ID instead of returning another person by numeric prefix' do
    get url.sub('/opportunities', 'junk/opportunities'), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'never returns another account contact or its count' do
    other = create(:contact)
    get "/api/v1/accounts/#{account.id}/crm/contacts/#{other.id}/opportunities", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to include(other.name)
    expect(response.parsed_body).not_to have_key('meta')
  end

  it 'requires authentication and the existing CRM enabled gate' do
    get url
    expect(response).to have_http_status(:unauthorized)
    with_modified_env('CRM_KANBAN_ENABLED' => 'false') do
      get url, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  it 'applies the existing card visibility scope to rows AND total counts' do
    agent, = create_crm_agent(account: account)
    card
    visible = account.crm_cards.create!(attributes.merge(owner: agent, title: 'Agent opportunity'))
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    expect(response.body).not_to include('Negotiation')
  end

  it 'does not serialize hidden conversations or internal data even when the card is visible' do
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account)
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    create_incoming_message(conversation: conversation, content: 'Private message body')
    account.crm_cards.create!(attributes.merge(owner: agent, primary_conversation: conversation,
                                               description: 'Private commercial detail', metadata: { 'secret' => 'Internal AI metadata' }))
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].length).to eq(1)
    expect(response.parsed_body['payload'].first.keys).to match_array(%w[id title status value_cents currency expected_close_at pipeline stage owner])
    %w[conversation metadata description contact email phone_number].each do |key|
      expect(response.parsed_body['payload'].first).not_to have_key(key)
    end
    expect(response.body).not_to include('Private message body', 'Internal AI metadata', contact.email)
  end
end
