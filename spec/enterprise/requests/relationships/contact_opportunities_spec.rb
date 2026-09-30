require 'rails_helper'

RSpec.describe 'Contact opportunities role boundaries', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_and_membership) { create_crm_agent(account: account) }
  let(:agent) { agent_and_membership.first }
  let(:membership) { agent_and_membership.last }
  let(:role) { create(:custom_role, account: account, permissions: %w[contact_view crm_view]) }
  let(:contact) { account.contacts.create!(name: 'Person') }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:attributes) { { pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last, contact: contact, title: 'Visible deal' } }
  let(:url) { "/api/v1/accounts/#{account.id}/crm/contacts/#{contact.id}/opportunities" }

  before do
    membership.update!(custom_role: role)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  it 'lets a CRM read-only seat read its permitted opportunities without granting writes' do
    visible = account.crm_cards.create!(attributes.merge(owner: agent))
    account.crm_cards.create!(attributes.merge(owner: admin, title: 'Hidden deal'))
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    post "/api/v1/accounts/#{account.id}/crm/cards", params: { card: { title: 'Not allowed' } }, headers: auth_headers(agent), as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  it 'denies a contact-view-only seat without exposing an empty list or count' do
    role.update!(permissions: ['contact_view'])
    account.crm_cards.create!(attributes.merge(owner: agent))
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body).not_to have_key('payload')
    expect(response.parsed_body).not_to have_key('meta')
  end

  it 'does not equate management permission with CRM viewing permission' do
    role.update!(permissions: %w[contact_view crm_manage_cards])
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'requires the contact show policy as well as CRM viewing' do
    allow(ContactPolicy).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |policy| allow(policy).to receive(:show?).and_return(false) }
    end
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)
  end

  it 'honors assigned-only inbox restrictions and recalculates after permission is revoked' do
    inbox = create_crm_inbox(account: account, members: [agent])
    Crm::InboxSetting.create!(account: account, inbox: inbox, visibility_mode: :assigned_only)
    visible = account.crm_cards.create!(attributes.merge(inbox: inbox, owner: agent))
    account.crm_cards.create!(attributes.merge(inbox: inbox, owner: admin, title: 'Assigned elsewhere'))
    get url, headers: auth_headers(agent)
    expect(response.parsed_body['payload'].pluck('id')).to eq([visible.id])
    expect(response.parsed_body.dig('meta', 'total_count')).to eq(1)
    role.update!(permissions: ['contact_view'])
    get url, headers: auth_headers(agent)
    expect(response).to have_http_status(:unauthorized)
  end
end
