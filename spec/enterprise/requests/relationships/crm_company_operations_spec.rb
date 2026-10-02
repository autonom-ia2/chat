require 'rails_helper'

RSpec.describe 'CRM shared company operations', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account, name: 'Horizonte', domain: 'horizonte.example', custom_attributes: { 'keep' => 0 }) }
  let(:other) { create(:company, account: account, name: 'Alameda', domain: 'alameda.example') }
  let(:contact) { create(:contact, account: account, company: company, custom_attributes: { 'keep' => false }) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: pipeline_and_stage.first, stage: pipeline_and_stage.last,
                              contact: contact, owner: admin, title: 'Original opportunity', value_cents: 123_400)
  end
  let(:headers) { admin.create_new_auth_token }
  let(:company_url) { "/api/v1/accounts/#{account.id}/companies/#{company.id}" }
  let(:contact_url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}" }

  before do
    account.enable_features!('companies')
    card
    conversation
  end

  it 'edits the shared company without touching the contact, opportunity or messages' do
    snapshot = card.reload.attributes
    contact_snapshot = contact.reload.attributes
    messages = Message.count
    patch company_url, headers: headers, params: { company: { name: 'Horizonte Seguros' } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(company.reload.name).to eq('Horizonte Seguros')
    expect(company.custom_attributes).to eq('keep' => 0)
    expect(contact.reload.attributes).to eq(contact_snapshot)
    expect(card.reload.attributes).to eq(snapshot)
    expect(Message.count).to eq(messages)
  end

  it 'clears the optional domain without deleting custom attributes' do
    patch company_url, headers: headers, params: { company: { domain: nil } }, as: :json
    expect(response).to have_http_status(:ok)
    expect(company.reload.domain).to be_nil
    expect(company.custom_attributes).to eq('keep' => 0)
  end

  it 'rolls back the whole edit when the domain belongs to another company' do
    other
    patch company_url, headers: headers, params: { company: { name: 'Must not persist', domain: other.domain } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(company.reload.name).to eq('Horizonte')
    expect(company.domain).to eq('horizonte.example')
  end

  it 'rejects invalid company data without a partial save' do
    patch company_url, headers: headers, params: { company: { name: '', description: 'Must not persist' } }, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(company.reload.name).to eq('Horizonte')
    expect(company.description).not_to eq('Must not persist')
  end

  it 'links an existing company while preserving opportunity, conversations and original files' do
    other
    snapshot = card.reload.attributes
    origin = conversation.reload.attributes
    counts = [Contact.count, Company.count, Crm::Card.count, Attachment.count, Message.count]
    patch contact_url, headers: headers, params: { company_id: other.id }, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'company_id')).to eq(other.id)
    expect(contact.reload).to have_attributes(company_id: other.id, custom_attributes: { 'keep' => false },
                                              additional_attributes: include('company_name' => 'Alameda'))
    expect(card.reload.attributes).to eq(snapshot)
    expect(conversation.reload.attributes).to eq(origin)
    expect([Contact.count, Company.count, Crm::Card.count, Attachment.count, Message.count]).to eq(counts)
    expect([company.reload.contacts_count, other.reload.contacts_count]).to eq([0, 1])
  end

  it 'removes the association without deleting the company or contact, even when repeated' do
    snapshot = card.reload.attributes
    2.times do
      patch contact_url, headers: headers, params: { company_id: nil }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'company_id')).to be_nil
    end
    expect(contact.reload.company_id).to be_nil
    expect(contact.additional_attributes).not_to have_key('company_name')
    expect(Company.exists?(company.id)).to be(true)
    expect(card.reload.attributes).to eq(snapshot)
    expect(conversation.reload.contact_id).to eq(contact.id)
  end

  it 'does not link a company from another account' do
    forbidden = create(:company)
    patch contact_url, headers: headers, params: { company_id: forbidden.id }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(contact.reload.company_id).to eq(company.id)
  end

  it 'does not edit a company from another account' do
    forbidden = create(:company)
    patch "/api/v1/accounts/#{account.id}/companies/#{forbidden.id}", headers: headers,
                                                                      params: { company: { name: 'Forbidden change' } }, as: :json
    expect(response).to have_http_status(:not_found)
    expect(forbidden.reload.name).not_to eq('Forbidden change')
  end

  it 'does not return a false new link when Companies is disabled' do
    other
    account.disable_features!('companies')
    patch contact_url, headers: headers, params: { company_id: other.id }, as: :json
    expect(response).to have_http_status(:ok)
    expect(contact.reload.company_id).to eq(company.id)
    expect(response.parsed_body.dig('payload', 'company_id')).not_to eq(other.id)
  end

  it 'searches identical company names by domain without merging records' do
    other.update!(name: company.name)
    get "/api/v1/accounts/#{account.id}/companies/search", headers: headers, params: { q: company.name }
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    expect(payload.pluck('id')).to contain_exactly(company.id, other.id)
    expect(payload.pluck('domain')).to contain_exactly(company.domain, other.domain)
  end
end
