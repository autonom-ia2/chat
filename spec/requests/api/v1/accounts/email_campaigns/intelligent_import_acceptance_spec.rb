require 'rails_helper'

RSpec.describe 'Email campaign intelligent import acceptance', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/recipients" }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  it 'accepts, persists, processes and presents the production semicolon regression through the real HTTP/job/database path' do
    upload = Rack::Test::UploadedFile.new(
      StringIO.new("NOME;E-MAIL;CORRETORA\nAna;ana@example.org;Alpha\nBia;bia@example.org;Beta\n"),
      'text/csv',
      original_filename: 'lista de teste chat2you.csv'
    )

    post base, params: { import_file: upload }, headers: headers
    expect(response).to have_http_status(:accepted)
    import = campaign.email_campaign_imports.sole
    expect(import.source_file).to be_attached

    EmailCampaigns::RecipientImportJob.perform_now(import.id)

    expect(import.reload).to be_completed
    expect(import.result).to include('imported' => 2, 'invalid' => 0, 'total' => 2)
    expect(import.schema_resolution).to include('method' => 'deterministic', 'delimiter' => ';', 'email_column' => 1)
    expect(campaign.email_campaign_recipients.order(:email).pluck(:email)).to eq(%w[ana@example.org bia@example.org])

    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaign', 'recipient_import')).to include(
      'status' => 'completed', 'result' => hash_including('imported' => 2, 'total' => 2)
    )
  end
end
