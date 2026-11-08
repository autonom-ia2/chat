require 'rails_helper'

RSpec.describe 'Campaign imports API', type: :request do
  around do |example|
    previous_value = ENV.fetch('CAMPAIGN_IMPORT_ENABLED', nil)
    ENV['CAMPAIGN_IMPORT_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CAMPAIGN_IMPORT_ENABLED')
    else
      ENV['CAMPAIGN_IMPORT_ENABLED'] = previous_value
    end
  end

  it 'streams generated CSV downloads for authenticated admins' do
    account, user = create_account_and_user
    content = "nome,telefone\nAna,11987654321\nBia,(11) 98765-4321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content)
    CampaignImports::Validator.new(campaign_import).perform

    get "/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}/download",
        params: { file: 'error_csv' },
        headers: auth_headers(user)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('attachment')
    expect(response.body).to include('duplicate_phone_in_file')
    expect(response.body).not_to include('11987654321')
  end

  # #2332: the files this app wrote open in Excel with accents and columns; the person's own upload goes back as it came.
  it 'downloads the normalized file with BOM and ";", and the original untouched' do
    account, user = create_account_and_user
    content = "nome,telefone\nFlávia,11987654321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content)
    campaign_import.normalized_csv.attach(io: StringIO.new("nome,telefone\nFlávia,+5511987654321\n"), filename: 'normalizado.csv',
                                          content_type: 'text/csv')
    path = "/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}/download"

    get path, params: { file: 'normalized_csv' }, headers: auth_headers(user)
    body = response.body.dup.force_encoding(Encoding::UTF_8)
    expect(body).to start_with("\uFEFF")
    expect(body.lines.first).to include(';')
    expect(body).to include('Flávia')

    get path, params: { file: 'original' }, headers: auth_headers(user)
    expect(response.body.b).to eq(campaign_import.original_file.download.b)
    expect(response.body.b).to start_with('nome,telefone')
  end

  it 'allows deleting an import before contacts are created' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform

    get "/api/v1/accounts/#{account.id}/campaign_imports", headers: auth_headers(user)

    payload = response.parsed_body['payload'].first
    expect(payload['base_label']).to eq(campaign_import.reload.base_label)
    expect(payload['can_delete']).to be(true)

    delete "/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}", headers: auth_headers(user)

    expect(response).to have_http_status(:no_content)
    expect(CampaignImport.exists?(campaign_import.id)).to be(false)
  end

  it 'blocks deleting an import that is queued for importing' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform
    campaign_import.update!(status: :queued)

    delete "/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}", headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CampaignImport.exists?(campaign_import.id)).to be(true)
    expect(account.contacts.count).to eq(0)
  end

  it 'blocks deleting an import after contacts are created' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform
    campaign_import.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import.reload).perform

    delete "/api/v1/accounts/#{account.id}/campaign_imports/#{campaign_import.id}", headers: auth_headers(user)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(CampaignImport.exists?(campaign_import.id)).to be(true)
    expect(account.contacts.count).to eq(2)
  end

  it 'blocks API endpoints when the feature flag is disabled' do
    account, user = create_account_and_user
    ENV['CAMPAIGN_IMPORT_ENABLED'] = 'false'

    get "/api/v1/accounts/#{account.id}/campaign_imports", headers: auth_headers(user)

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['error']).to eq('campaign_import.disabled')
  end

  def auth_headers(user)
    { 'api_access_token' => user.access_token.token }
  end
end
