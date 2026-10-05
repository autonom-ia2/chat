require 'rails_helper'

# Importar contatos (#1006, PRD §8.7): the journey's contact import API.
RSpec.describe 'Contact imports API (#1006)', :aggregate_failures, type: :request do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:admin) { account_and_user.last }
  let(:content) { "Segurado;Fone 1;Corretora;Vencimento\nAna Souza;11987654321;Alfa;10/2026\nBia Lima;21987654321;Beta;\n" }
  let(:flags) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

  around do |example|
    with_modified_env(flags) { example.run }
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end

  def upload(text, filename: 'contatos.csv')
    file = Tempfile.new(['contatos', '.csv'])
    file.write(text)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'text/csv', original_filename: filename)
  end

  def imports_path(*parts)
    ["/api/v1/accounts/#{account.id}/contact_imports", *parts].join('/')
  end

  def create_import(user = admin)
    perform_enqueued_jobs do
      post imports_path, params: { import_file: upload(content) }, headers: auth_headers(user)
    end
    account.campaign_imports.last
  end

  def agent_with(permissions: nil)
    agent = create(:user, account: account, role: :agent)
    agent.account_users.first.update!(custom_role: create(:custom_role, account: account, permissions: permissions)) if permissions
    agent
  end

  # B2 / Q3 through the API: Jev off -> choose the columns, then import; extras become attributes.
  it 'uploads, asks for the columns, imports contacts and attributes and stays out of Públicos' do
    contact_import = create_import

    expect(response).to have_http_status(:created)
    expect(response.parsed_body['payload']).to include('flow' => 'contacts')
    expect(contact_import.reload).to be_needs_column_choice
    expect(contact_import).to be_contact_import

    perform_enqueued_jobs do
      patch imports_path(contact_import.id, 'columns'), params: { name: 0, phone: 1, company: 2 }, headers: auth_headers(admin), as: :json
    end
    expect(response).to have_http_status(:ok)
    expect(contact_import.reload).to be_ready_to_confirm
    expect(contact_import.validation_summary['contact_attributes'].pluck('key')).to eq(['vencimento'])

    perform_enqueued_jobs { post imports_path(contact_import.id, 'confirm'), headers: auth_headers(admin) }

    expect(response).to have_http_status(:ok)
    expect(contact_import.reload).to be_completed
    expect(account.contacts.order(:name).pluck(:name, :phone_number, :custom_attributes)).to eq(
      [['Ana Souza', '+5511987654321', { 'vencimento' => '10/2026' }], ['Bia Lima', '+5521987654321', {}]]
    )
    expect(Label.count).to eq(0)

    get "/api/v1/accounts/#{account.id}/campaign_imports", headers: auth_headers(admin)
    expect(response.parsed_body['payload']).to be_empty
    expect(response.parsed_body['meta']['count']).to eq(0)

    get "/api/v1/accounts/#{account.id}/campaign_imports/#{contact_import.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end

  it 'is not usable as a campaign audience' do
    contact_import = create_import
    contact_import.update!(status: :completed, imported_contacts_count: 2)

    patch "/api/v1/accounts/#{account.id}/campaign_imports/#{contact_import.id}/columns",
          params: { phone: 1 }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:not_found)

    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns",
         params: { campaign_import_id: contact_import.id, channel: 'whatsapp_cloud', campaign: { title: 'X' } },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:not_found)
    expect(CampaignAudienceLink.count).to eq(0)
  end

  it 'turns "Criar e ligar" off and refuses to import before the file is ready' do
    contact_import = create_import

    patch imports_path(contact_import.id, 'companies'), params: { create_companies: false }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']['create_companies']).to be(false)

    post imports_path(contact_import.id, 'confirm'), headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.not_ready')
  end

  it 'downloads the rows left out and drops a draft' do
    perform_enqueued_jobs do
      post imports_path, params: { import_file: upload("Nome;Celular\nAna;123\nBia;21987654321\n") }, headers: auth_headers(admin)
    end
    contact_import = account.campaign_imports.last
    perform_enqueued_jobs do
      patch imports_path(contact_import.id, 'columns'), params: { name: 0, phone: 1 }, headers: auth_headers(admin), as: :json
    end
    expect(contact_import.reload).to have_attributes(status: 'ready_to_confirm', valid_rows: 1, invalid_rows: 1)

    get imports_path(contact_import.id, 'download'), headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('invalid_brazilian_mobile_number')

    delete imports_path(contact_import.id), headers: auth_headers(admin)
    expect(response).to have_http_status(:no_content)
    expect(account.contacts.count).to eq(0)
  end

  describe 'permissions (same as Chatwoot contact import)' do
    it 'refuses an agent without contact_manage and accepts a custom role with it' do
      post imports_path, params: { import_file: upload(content) }, headers: auth_headers(agent_with)
      expect(response).to have_http_status(:unauthorized)

      post imports_path, params: { import_file: upload(content) }, headers: auth_headers(agent_with(permissions: ['campaign_manage']))
      expect(response).to have_http_status(:unauthorized)

      post imports_path, params: { import_file: upload(content) }, headers: auth_headers(agent_with(permissions: ['contact_manage']))
      expect(response).to have_http_status(:created)
    end

    it 'does not let an agent read an import' do
      contact_import = create_import

      get imports_path(contact_import.id), headers: auth_headers(agent_with)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'flags' do
    [
      { 'CAMPAIGN_JOURNEY_ENABLED' => 'false', 'CAMPAIGN_IMPORT_ENABLED' => 'true' },
      { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'false' }
    ].each do |off|
      context "with #{off.select { |_key, value| value == 'false' }.keys.first} off" do
        let(:flags) { off }

        it 'answers 404 and leaves Chatwoot contact import working as before' do
          post imports_path, params: { import_file: upload(content) }, headers: auth_headers(admin)
          expect(response).to have_http_status(:not_found)
          expect(response.parsed_body['error']).to eq('contact_import.disabled')

          post "/api/v1/accounts/#{account.id}/contacts/import", params: { import_file: upload(content) }, headers: auth_headers(admin)
          expect(response).to have_http_status(:ok)
          expect(account.data_imports.last).to have_attributes(data_type: 'contacts')
          expect(account.campaign_imports.count).to eq(0)
        end
      end
    end
  end
end
