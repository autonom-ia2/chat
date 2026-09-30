require 'rails_helper'

RSpec.describe 'Email recipient import permissions', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:role) { create(:custom_role, account: account, permissions: permissions) }
  let(:headers) { user.create_new_auth_token }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/recipients" }
  let(:upload) do
    Rack::Test::UploadedFile.new(StringIO.new("Email\nsynthetic@example.org\n"), 'text/csv', original_filename: 'recipients.csv')
  end

  before do
    user.account_users.find_by!(account: account).update!(custom_role: role)
  end

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                      EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  context 'with campaign_view only' do
    let(:permissions) { ['campaign_view'] }

    it 'can read recipients but cannot upload a replacement or retry an existing file' do
      import = campaign.email_campaign_imports.create!(status: :failed, error_code: 'typesafe_unavailable')
      import.source_file.attach(io: StringIO.new("Email\nsynthetic@example.org\n"), filename: 'recipients.csv', identify: false)

      get path, headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      post path, params: { import_file: upload }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(campaign.email_campaign_imports.count).to eq(1)
      post "#{path}/retry_import", headers: headers, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(import.reload).to be_failed
      expect(EmailCampaigns::RecipientImportJob).not_to have_been_enqueued
    end
  end

  context 'with campaign_manage' do
    let(:permissions) { ['campaign_manage'] }

    it 'can import a file' do
      expect do
        post path, params: { import_file: upload }, headers: headers
      end.to have_enqueued_job(EmailCampaigns::RecipientImportJob)
      expect(response).to have_http_status(:accepted)
    end

    it 'can retry a saved file' do
      import = campaign.email_campaign_imports.create!(status: :failed, error_code: 'typesafe_unavailable')
      import.source_file.attach(io: StringIO.new("Email\nsynthetic@example.org\n"), filename: 'recipients.csv', identify: false)

      expect do
        post "#{path}/retry_import", headers: headers, as: :json
      end.to have_enqueued_job(EmailCampaigns::RecipientImportJob).with(import.id)
      expect(response).to have_http_status(:accepted)
    end
  end
end
