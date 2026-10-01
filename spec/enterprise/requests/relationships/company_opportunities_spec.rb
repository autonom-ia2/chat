require 'rails_helper'

RSpec.describe 'Company opportunities from linked contacts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { account.companies.create!(name: 'Company', domain: 'company.example') }
  let(:person) { account.contacts.create!(name: 'Person One', company_id: company.id) }
  let(:second_person) { account.contacts.create!(name: 'Person Two', company_id: company.id) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:attributes) { { pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: person, owner: admin, title: 'Renewal' } }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/companies/#{company.id}/opportunities" }
  let(:headers) { auth_headers(admin) }

  before do
    account.enable_features!('companies')
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  it 'reads the minimal projection without altering the company, contact or opportunity' do
    card = account.crm_cards.create!(attributes.merge(value_cents: 0, currency: 'USD'))
    snapshots = [company, person, card].map { |record| record.reload.attributes }
    expect { get url, headers: headers }.to not_change(Crm::Card, :count).and not_change(Company, :count).and not_change(Contact, :count)
    expect(response).to have_http_status(:ok)
    row = response.parsed_body.fetch('payload').first
    expect(row.keys).to match_array(%w[id title status value_cents currency expected_close_at pipeline stage owner contact])
    expect(row).to include('id' => card.id, 'value_cents' => 0, 'currency' => 'USD', 'contact' => { 'id' => person.id, 'name' => person.name })
    expect([company, person, card].map { |record| record.reload.attributes }).to eq(snapshots)
  end

  it 'uses all linked contacts across pipelines, not only the first contact page' do
    first = account.crm_cards.create!(attributes)
    pipeline, stage = create_crm_pipeline(account: account, user: admin, name: 'Renewals')
    second = account.crm_cards.create!(attributes.merge(contact: second_person, pipeline: pipeline, stage: stage, status: :won))
    26.times { |index| account.contacts.create!(name: "Additional #{index}", company_id: company.id) }
    last = account.contacts.create!(name: 'Last linked person', company_id: company.id)
    third = account.crm_cards.create!(attributes.merge(contact: last))
    get url, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to contain_exactly(first.id, second.id, third.id)
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(3)
  end

  it 'does not aggregate company homonyms or company names saved as legacy text' do
    card = account.crm_cards.create!(attributes)
    homonym = account.companies.create!(name: company.name)
    other = account.contacts.create!(name: person.name, company_id: homonym.id)
    legacy = account.contacts.create!(name: 'Legacy', additional_attributes: { company_name: company.name })
    [other, legacy, nil].each { |contact| account.crm_cards.create!(attributes.merge(contact: contact)) }
    get url, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([card.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
  end

  it 'reflects reassignment and unlink without changing the opportunities' do
    card = account.crm_cards.create!(attributes)
    destination = account.companies.create!(name: 'New Company')
    person.update!(company_id: destination.id)
    snapshot = card.reload.attributes
    get url, headers: headers
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(0)
    destination_url = "/api/v1/accounts/#{account.id}/crm/companies/#{destination.id}/opportunities"
    get destination_url, headers: headers
    expect(response.parsed_body.fetch('payload').pluck('id')).to eq([card.id])
    person.update!(company_id: nil)
    get destination_url, headers: headers
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(0)
    expect(card.reload.attributes).to eq(snapshot)
  end

  it 'excludes archived by default and applies each requested status' do
    %w[open won lost archived].each { |status| account.crm_cards.create!(attributes.merge(status: status, contact: second_person)) }
    get url, headers: headers
    expect(response.parsed_body['payload'].pluck('status')).to match_array(%w[open won lost])
    %w[open won lost archived].each do |status|
      get url, params: { result: status }, headers: headers
      expect(response.parsed_body['payload'].pluck('status')).to eq([status])
      expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    end
    get url, params: { result: 'all' }, headers: headers
    expect(response.parsed_body['payload'].pluck('status')).to match_array(%w[open won lost archived])
  end

  it 'paginates deterministically across contacts with at most five rows' do
    cards = Array.new(7) { account.crm_cards.create!(attributes.merge(updated_at: Time.utc(2026, 9, 30))) }
    get url, params: { per_page: 100 }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq(cards.last(5).reverse.map(&:id))
    expect(response.parsed_body['meta']).to include('per_page' => 5, 'total_count' => 7, 'has_more' => true)
    get url, params: { page: 2 }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq(cards.first(2).reverse.map(&:id))
    expect(response.parsed_body.dig('meta', 'has_more')).to be(false)
  end

  it 'searches title fragments literally and returns a real empty state' do
    match = account.crm_cards.create!(attributes.merge(title: 'RENOVAÇÃO 50%_VIP'))
    account.crm_cards.create!(attributes.merge(title: 'Renovação 500 VIP'))
    get url, params: { search: '  50%_vip ' }, headers: headers
    expect(response.parsed_body['payload'].pluck('id')).to eq([match.id])
    get url, params: { search: 'Not present' }, headers: headers
    expect(response.parsed_body).to eq('payload' => [], 'meta' => { 'total_count' => 0, 'page' => 1, 'per_page' => 5, 'has_more' => false })
  end

  [{ page: '0' }, { page: '-1' }, { page: '1x' }, { page: ['1'] }, { search: ['term'] },
   { result: ['all'] }, { result: 'unknown' }, { search: 'x' * 201 }].each do |input|
    it "rejects invalid #{input.keys.first} of type #{input.values.first.class}" do
      get url, params: input, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).not_to have_key('payload')
    end
  end

  it 'rejects malformed company identities and companies of other accounts' do
    get url.sub('/opportunities', 'junk/opportunities'), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
    other = create(:company)
    get "/api/v1/accounts/#{account.id}/crm/companies/#{other.id}/opportunities", headers: headers
    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body).not_to have_key('meta')
    expect(response.body).not_to include(other.name)
  end

  it 'requires authentication, the CRM gate and Companies feature' do
    get url
    expect(response).to have_http_status(:unauthorized)
    allow(Crm::Config).to receive(:enabled?).and_return(false)
    get url, headers: headers
    expect(response).to have_http_status(:not_found)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    account.disable_features!('companies')
    get url, headers: headers
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body).not_to have_key('payload')
  end

  it 'requires company reading as well as CRM viewing' do
    allow(CompanyPolicy).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |policy| allow(policy).to receive(:show?).and_return(false) }
    end
    get url, headers: headers
    expect(response).to have_http_status(:unauthorized)
  end

  it 'allows a read-only CRM role only its rows and count across contacts and honors revoked access' do
    agent, membership = create_crm_agent(account: account)
    role = create(:custom_role, account: account, permissions: %w[contact_view crm_view])
    membership.update!(custom_role: role)
    allowed = account.crm_cards.create!(attributes.merge(owner: agent, contact: second_person))
    account.crm_cards.create!(attributes.merge(title: 'Restricted negotiation', status: :won))
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([allowed.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    expect(response.body).not_to include('Restricted negotiation')
    get url, params: { result: 'won' }, headers: auth_headers(agent)
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(0)
    role.update!(permissions: %w[contact_view crm_manage_cards])
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'respects assigned-only inbox restrictions and returns no conversation data' do
    agent, = create_crm_agent(account: account)
    inbox = create_crm_inbox(account: account, members: [agent])
    Crm::InboxSetting.create!(account: account, inbox: inbox, visibility_mode: :assigned_only)
    allowed = account.crm_cards.create!(attributes.merge(owner: agent, inbox: inbox))
    account.crm_cards.create!(attributes.merge(inbox: inbox, owner: admin, title: 'Assigned elsewhere'))
    get url, headers: auth_headers(agent)
    expect(response.parsed_body['payload'].pluck('id')).to eq([allowed.id])
    expect(response.parsed_body['payload'].first['contact'].keys).to match_array(%w[id name])
    expect(response.body).not_to include('Assigned elsewhere', 'phone_number', 'conversation_id', 'metadata')
  end
end
