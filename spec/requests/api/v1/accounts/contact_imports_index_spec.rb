require 'rails_helper'

# Contatos > Importações (#2771, decision 15): the account's contact imports, from a file or from the automation step
# "para cada item". Only flow "contacts" of this account; same permission as the contact import.
RSpec.describe 'Contact imports list API (#2771)', :aggregate_failures, type: :request do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:flags) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

  around { |example| with_modified_env(flags) { example.run } }

  def auth_headers(user) = { 'api_access_token' => user.access_token.token }

  def list(user = admin, page: nil)
    get "/api/v1/accounts/#{account.id}/contact_imports", params: { page: page }.compact, headers: auth_headers(user)
  end

  def import_of(target_account, user: admin, options: { flow: CampaignImport::CONTACTS_FLOW }, **attributes)
    target_account.campaign_imports.create!(user: user, status: :completed, options: options, **attributes)
  end

  def agent_with(permissions: nil)
    agent = create(:user, account: account, role: :agent)
    agent.account_users.first.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) if permissions
    agent
  end

  it 'lists only the contact imports of the account, newest first, with origin, who and the counts' do
    from_file = import_of(account, source_filename: 'clientes.csv', total_rows: 3, imported_contacts_count: 2, invalid_rows: 1,
                                   created_at: 2.days.ago)
    automation_options = { flow: CampaignImport::CONTACTS_FLOW, origem: CampaignImport::AUTOMATION_ORIGIN, automacao_id: 7 }
    from_automation = import_of(account, name: 'Lista do RH', options: automation_options, total_rows: 4, imported_contacts_count: 3,
                                         failed_contacts_count: 1, created_at: 1.day.ago)
    import_of(account, options: { flow: CampaignImport::AUDIENCE_FLOW })
    import_of(account, options: {})
    other_account = create(:account)
    import_of(other_account, user: create(:user, account: other_account))

    list

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload.pluck('id')).to eq([from_automation.id, from_file.id])
    expect(payload.first).to include('origin' => 'automation', 'name' => 'Lista do RH', 'status' => 'completed',
                                     'imported_contacts_count' => 3, 'failed_count' => 1, 'total_rows' => 4)
    expect(payload.first['created_by']).to eq('id' => admin.id, 'name' => admin.name)
    expect(payload.last).to include('origin' => 'file', 'imported_contacts_count' => 2, 'failed_count' => 1)
    expect(payload.map(&:keys).flatten).not_to include('source_filename')
    expect(response.parsed_body['meta']).to eq('count' => 2, 'current_page' => 1, 'per_page' => 25)
  end

  it 'pages 25 at a time' do
    26.times { |index| import_of(account, created_at: index.minutes.ago) }

    list(page: 2)

    expect(response.parsed_body['payload'].size).to eq(1)
    expect(response.parsed_body['meta']).to include('count' => 26, 'current_page' => 2)
  end

  it 'opens an automation import by id with its origin and the rows left out, phone masked and no name' do
    contact_import = import_of(account, status: :completed_with_failures, total_rows: 2, invalid_rows: 1,
                                        options: { flow: CampaignImport::CONTACTS_FLOW, origem: CampaignImport::AUTOMATION_ORIGIN })
    contact_import.campaign_import_rows.create!(row_number: 2, raw_name: 'Zé', raw_phone_masked: '+55 •••••-0123', status: :invalid,
                                                error_messages: ['invalid_brazilian_mobile_number'])

    get "/api/v1/accounts/#{account.id}/contact_imports/#{contact_import.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body['payload']
    expect(payload).to include('origin' => 'automation', 'flow' => 'contacts')
    expect(payload['problem_rows']).to eq([{ 'row_number' => 2, 'phone' => '+55 •••••-0123', 'email' => nil,
                                             'errors' => ['invalid_brazilian_mobile_number'] }])
    expect(payload['problem_rows'].to_json).not_to include('Zé')
  end

  it 'answers 404 when the id is of another account or of a Públicos audience' do
    other_account = create(:account)
    from_other_account = import_of(other_account, user: create(:user, account: other_account))
    audience = import_of(account, options: { flow: CampaignImport::AUDIENCE_FLOW })

    [from_other_account, audience].each do |campaign_import|
      get "/api/v1/accounts/#{account.id}/contact_imports/#{campaign_import.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'permissions (same as the contact import)' do
    before { import_of(account) }

    it 'refuses an agent without contact_manage and a campaign role, and accepts a custom role with contact_manage' do
      list(agent_with)
      expect(response).to have_http_status(:unauthorized)

      list(agent_with(permissions: ['campaign_manage']))
      expect(response).to have_http_status(:unauthorized)

      list(agent_with(permissions: ['contact_manage']))
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload'].size).to eq(1)
    end

    it 'does not answer for an account the user is not in' do
      other_account = create(:account)

      get "/api/v1/accounts/#{other_account.id}/contact_imports", headers: auth_headers(admin)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with the journey off' do
    let(:flags) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'false', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

    it 'answers 404' do
      list

      expect(response).to have_http_status(:not_found)
    end
  end
end
