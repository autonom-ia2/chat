require 'rails_helper'

RSpec.describe 'CRM contact lookup with canonical company', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:company) { create(:company, account: account, name: 'Horizonte Seguros', domain: 'horizonte.example') }
  let(:contact) { create(:contact, account: account, name: 'Mariana', email: 'person@example.com', company: company) }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/search" }
  let(:headers) { admin.create_new_auth_token }

  before do
    account.enable_features!('companies')
    contact
  end

  it 'finds a contact by the linked company and returns its canonical identity' do
    get url, params: { q: 'Horizonte', include_company: 'true', include_contact_inboxes: false }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload').map { |item| item['id'] }).to eq([contact.id])
    expect(response.parsed_body.dig('payload', 0, 'company')).to eq('id' => company.id, 'name' => company.name, 'domain' => company.domain)
  end

  it 'also searches the domain without requiring it in the contact email' do
    get url, params: { q: 'horizonte.example', include_company: 'true' }, headers: headers
    expect(response.parsed_body.fetch('payload').map { |item| item['id'] }).to eq([contact.id])
  end

  it 'preserves the standard search and payload unless the optional contract is requested' do
    get url, params: { q: 'Horizonte' }, headers: headers
    expect(response.parsed_body.fetch('payload')).to be_empty
    get url, params: { q: 'Mariana' }, headers: headers
    expect(response.parsed_body.fetch('payload').first).not_to have_key('company')
  end

  it 'does not infer an association from a legacy company name' do
    contact.update!(company: nil)
    contact.update!(additional_attributes: { company_name: 'Horizonte Seguros' })
    get url, params: { q: 'Horizonte', include_company: 'true' }, headers: headers
    expect(response.parsed_body.fetch('payload')).to be_empty
    get url, params: { q: 'Mariana', include_company: 'true' }, headers: headers
    expect(response.parsed_body.dig('payload', 0, 'company')).to be_nil
  end

  it 'keeps namesakes from another account outside the result' do
    foreign = create(:company, name: company.name, domain: company.domain)
    create(:contact, account: foreign.account, company: foreign, name: 'Foreign private contact')
    get url, params: { q: 'Horizonte', include_company: 'true' }, headers: headers
    expect(response.parsed_body.fetch('payload').map { |item| item['id'] }).to eq([contact.id])
    expect(response.body).not_to include('Foreign private contact')
  end

  it 'ignores company lookup and company details when Companies is disabled' do
    account.disable_features!('companies')
    get url, params: { q: 'Horizonte', include_company: 'true' }, headers: headers
    expect(response.parsed_body.fetch('payload')).to be_empty
    get url, params: { q: 'Mariana', include_company: 'true' }, headers: headers
    expect(response.parsed_body.fetch('payload').first).not_to have_key('company')
  end

  it 'uses server pagination and has_more instead of loading every contact' do
    16.times { |index| create(:contact, account: account, company: company, name: "Pessoa #{index.to_s.rjust(2, '0')}") }
    get url, params: { q: 'Horizonte', include_company: 'true', page: 1 }, headers: headers
    first_ids = response.parsed_body.fetch('payload').map { |item| item['id'] }
    expect(first_ids.length).to eq(15)
    expect(response.parsed_body.dig('meta', 'has_more')).to be(true)
    get url, params: { q: 'Horizonte', include_company: 'true', page: 2 }, headers: headers
    second_ids = response.parsed_body.fetch('payload').map { |item| item['id'] }
    expect(second_ids.length).to eq(2)
    expect(first_ids & second_ids).to be_empty
    expect(response.parsed_body.dig('meta', 'has_more')).to be(false)
  end
end
