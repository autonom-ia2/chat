require 'rails_helper'

RSpec.describe 'Campaign import audiences API (Públicos, #992)', :aggregate_failures, type: :request do
  around do |example|
    previous_value = ENV.fetch('CAMPAIGN_IMPORT_ENABLED', nil)
    ENV['CAMPAIGN_IMPORT_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CAMPAIGN_IMPORT_ENABLED') : ENV['CAMPAIGN_IMPORT_ENABLED'] = previous_value
  end

  let(:content) { "Segurado;Fone 1;Corretora;Vencimento\nAna Souza;11987654321;Alfa;10/2026\nBia Lima;21987654321;Beta;\n" }

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end

  def upload(content)
    file = Tempfile.new(['publico', '.csv'])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, 'text/csv', original_filename: 'publico.csv')
  end

  def import_path(account, campaign_import, action = nil)
    ["/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}", action].compact.join('/')
  end

  # B2: Jev off -> the screen asks for the columns, and the import concludes afterwards.
  it 'creates an audience, waits for the column choice, then validates and imports with the chosen columns' do
    account, user = create_account_and_user

    perform_enqueued_jobs do
      post "/api/v1/accounts/#{account.id}/campaign_imports", params: { name: 'Clientes', import_file: upload(content) }, headers: auth_headers(user)
    end

    expect(response).to have_http_status(:created)
    campaign_import = account.campaign_imports.last
    expect(campaign_import.reload).to be_needs_column_choice
    expect(campaign_import).to be_audience

    get import_path(account, campaign_import), headers: auth_headers(user)
    payload = response.parsed_body['payload']
    expect(payload).to include('status' => 'needs_column_choice', 'name' => 'Clientes', 'flow' => 'audience')
    expect(payload['schema_resolution']).to include('method' => 'deterministic', 'needs_confirmation' => true)
    expect(payload['schema_resolution']['columns'].pluck('header')).to eq(['Segurado', 'Fone 1', 'Corretora', 'Vencimento'])

    perform_enqueued_jobs do
      patch import_path(account, campaign_import, 'columns'), params: { name: 0, phone: 1, email: nil, company: 2 },
                                                              headers: auth_headers(user), as: :json
    end
    expect(response).to have_http_status(:ok)
    campaign_import.reload
    expect(campaign_import).to be_ready_to_confirm
    expect(campaign_import.schema_resolution['method']).to eq('manual')
    expect(campaign_import.extra_columns).to eq(['Vencimento'])

    perform_enqueued_jobs do
      post import_path(account, campaign_import, 'confirm'), headers: auth_headers(user)
    end
    expect(campaign_import.reload).to be_completed
    expect(account.contacts.order(:name).pluck(:name, :phone_number)).to eq([['Ana Souza', '+5511987654321'], ['Bia Lima', '+5521987654321']])
  end

  it 'refuses a column choice without phone or email, or outside the table' do
    account, user = create_account_and_user
    campaign_import = create_audience_import(account: account, user: user, content: content)
    CampaignImports::AudienceValidator.new(campaign_import).perform

    patch import_path(account, campaign_import, 'columns'), params: { name: 0, company: 2 }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.invalid_column_choice')

    patch import_path(account, campaign_import, 'columns'), params: { phone: 9 }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(campaign_import.reload).to be_needs_column_choice
  end

  it 'refuses the column choice on an old campaign base import' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")

    patch import_path(account, campaign_import, 'columns'), params: { phone: 1 }, headers: auth_headers(user), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.not_an_audience')
  end

  it 'returns variable suggestions and the rows a variable mapping leaves out' do
    account, user = create_account_and_user
    campaign_import = create_audience_import(account: account, user: user, content: content)
    manual = { 'name' => 0, 'phone' => 1, 'company' => 2 }
    campaign_import.update!(schema_resolution: { 'manual_mapping' => manual, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform

    get import_path(account, campaign_import, 'variable_suggestions'),
        params: { variables: [{ key: '2', label: 'mês de vencimento' }] }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to eq([{ 'key' => '2', 'source' => nil, 'confidence' => nil }])

    post import_path(account, campaign_import, 'variable_coverage'),
         params: { mapping: { '2' => { source: 'extra', column: 'Vencimento' } } }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['payload']).to include('included_count' => 1, 'excluded_count' => 1,
                                                       'excluded' => [{ 'row_number' => 3, 'missing' => ['2'] }])

    post import_path(account, campaign_import, 'variable_coverage'),
         params: { mapping: { '2' => { source: 'extra', column: 'CPF' } } }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('campaign_import.invalid_variable_mapping')
  end

  it 'keeps the column choice behind campaign_manage' do
    account, user = create_account_and_user
    agent = User.create!(name: 'Agente', email: "agente-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: agent, role: :agent)
    campaign_import = create_audience_import(account: account, user: user, content: content)
    CampaignImports::AudienceValidator.new(campaign_import).perform

    patch import_path(account, campaign_import, 'columns'), params: { phone: 1 }, headers: auth_headers(agent), as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(campaign_import.reload).to be_needs_column_choice
  end
end
