require 'rails_helper'

# #2414 review: the people of an audience are contacts of the base, whatever the audience's origin. Who does not read
# contacts (ContactPolicy#index?; EE: contact_view) sees phone and e-mail masked, no company, and cannot download the list.
RSpec.describe 'Campaign import audience contact mask', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) do
    create(:contact, account: account, name: 'Ana Lima', phone_number: '+5511987654321', email: 'ana@example.com',
                     additional_attributes: { 'company_name' => 'Alfa Seguros' })
  end
  let(:audience) do
    row = CampaignJourney::AudienceWriter::Row.new(
      contact_id: contact.id, name: contact.name, phone: ConversationAudience::Reach.phone(contact),
      email: ConversationAudience::Reach.email(contact), company_name: 'Alfa Seguros', extra_values: {}
    )
    CampaignJourney::AudienceWriter.new(account, user: admin, source: Autonomia::Prospecting::AudienceFromLeads::SOURCE)
                                   .perform('Leads de outubro', [row])
  end
  let(:audience_path) { "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}" }

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def with_role(permissions)
    create(:user, account: account, role: :agent).tap do |user|
      role = create(:custom_role, account: account, permissions: permissions)
      user.account_users.find_by(account: account).update!(custom_role: role)
    end
  end

  describe 'an audience from prospecting' do
    it 'masks phone and e-mail and hides the company of the contacts list for a campaign_view role without contact_view' do
      get "#{audience_path}/contacts", headers: headers(with_role(%w[campaign_view]))

      expect(response).to have_http_status(:ok)
      hidden = response.parsed_body['payload'].sole
      expect(hidden).to include('id' => contact.id, 'name' => 'Ana L.', 'company_name' => nil)
      expect([hidden['phone_number'], hidden['email']]).to all(be_present)
      expect(response.body).not_to include('Ana Lima', '987654321', 'ana@example.com', 'Alfa Seguros')
    end

    it 'shows the contact data to a role with contact_view or contact_manage, and to the administrator' do
      [with_role(%w[campaign_view contact_view]), with_role(%w[campaign_view contact_manage]), admin].each do |user|
        get "#{audience_path}/contacts", headers: headers(user)

        expect(response.parsed_body['payload'].sole).to include('name' => 'Ana Lima', 'phone_number' => '+5511987654321',
                                                                'email' => 'ana@example.com', 'company_name' => 'Alfa Seguros')
      end
    end

    it 'refuses the download to a campaign_manage role without contact_view, and gives it with contact_view' do
      get "#{audience_path}/people_sheet", headers: headers(with_role(%w[campaign_manage]))
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('campaign_import.contacts_hidden')

      get "#{audience_path}/people_sheet", headers: headers(with_role(%w[campaign_manage contact_view]))
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to include('spreadsheetml.sheet')
    end

    it 'masks the name and hides the company of the message preview from a campaign_manage role without contact_view' do
      get "#{audience_path}/sample_contact", headers: headers(with_role(%w[campaign_manage]))
      expect(response.parsed_body['payload']).to include('name' => 'Ana L.', 'first_name' => 'Ana', 'company_name' => nil,
                                                         'extra_values' => {})

      get "#{audience_path}/sample_contact", headers: headers(with_role(%w[campaign_manage contact_view]))
      expect(response.parsed_body['payload']).to include('company_name' => 'Alfa Seguros')
    end
  end

  describe 'download of the audience files' do
    let(:path) { "#{audience_path}/download" }

    before do
      audience.normalized_csv.attach(io: StringIO.new("nome,telefone\nAna Lima,+5511987654321\n"), filename: 'normalizado.csv',
                                     content_type: 'text/csv')
      audience.original_file.attach(io: StringIO.new("nome,telefone\nAna Lima,11987654321\n"), filename: 'publico.csv',
                                    content_type: 'text/csv')
    end

    it 'refuses the normalized and the original file to a campaign_manage role without contact_view' do
      manager = with_role(%w[campaign_manage])
      %w[normalized_csv original].each do |file|
        get path, params: { file: file }, headers: headers(manager)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('campaign_import.contacts_hidden')
        expect(response.body).not_to include('987654321')
      end
    end

    it 'gives both files to a campaign_manage role with contact_view' do
      reader = with_role(%w[campaign_manage contact_view])
      %w[normalized_csv original].each do |file|
        get path, params: { file: file }, headers: headers(reader)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('987654321')
      end
    end
  end

  it 'masks a spreadsheet audience the same way' do
    sheet = create_audience_import(account: account, user: admin, content: "nome,telefone\nAna,11987654321\n")
    sheet.campaign_import_rows.create!(row_number: 2, status: 'imported', contact: contact, raw_phone_masked: '+55 11 9****-4321')

    get "/api/v1/accounts/#{account.id}/campaign_imports/#{sheet.id}/contacts", headers: headers(with_role(%w[campaign_view]))

    expect(response.parsed_body['payload'].sole).to include('name' => 'Ana L.', 'phone_number' => '+55 11 9****-4321', 'email' => nil,
                                                            'company_name' => nil)
    expect(response.body).not_to include('Ana Lima', '987654321', 'ana@example.com', 'Alfa Seguros')
  end
end
