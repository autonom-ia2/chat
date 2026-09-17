require 'rails_helper'

RSpec.describe 'Email campaign recipient presentation #436', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns/campaigns" }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:upload) do
    Rack::Test::UploadedFile.new(StringIO.new("email\nsynthetic@example.org\n"), 'text/csv', original_filename: 'recipients.csv')
  end

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  # Request specs render the real Jbuilder views and authenticate through API tokens.
  it 'renders recipients with the same campaign DTO as detail and the batched list' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    get "#{base}/#{campaign.id}/recipients", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.fetch('payload')
    dto = payload.fetch('campaign')
    expect(payload.fetch('recipients').pluck('id')).to eq([recipient.id])
    expect(dto.keys).to include('preflight', 'protection', 'recipient_import', 'pause_reason', 'subject', 'body_html')

    get "#{base}/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq(dto)
    get base, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaigns').sole).to eq(dto)
  end

  it 'returns 202 with the shared DTO after persisting and enqueueing a real multipart upload' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign)
    expect do
      post "#{base}/#{campaign.id}/recipients", params: { import_file: upload }, headers: headers
    end.to have_enqueued_job(EmailCampaigns::RecipientImportJob)
    expect(response).to have_http_status(:accepted)
    payload = response.parsed_body.fetch('payload')
    dto = payload.fetch('campaign')
    import = campaign.email_campaign_imports.sole
    expect(import).to be_queued
    expect(import.source_file).to be_attached
    expect(dto.fetch('recipient_import')).to include('id' => import.id, 'status' => 'queued')
    expect(dto.dig('preflight', 'can_recheck')).to be(false)
    expect(payload.fetch('recipients')).to eq([])
    expect(campaign.email_campaign_recipients.pluck(:id)).to eq([recipient.id])

    get "#{base}/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq(dto)
  end

  it 'returns 202 with the shared DTO when retrying the same persisted import' do
    import = campaign.email_campaign_imports.create!(status: :failed, error_code: 'import_failed', completed_at: Time.current)
    import.source_file.attach(io: StringIO.new("email\nsynthetic@example.org\n"), filename: 'recipients.csv', identify: false)
    expect do
      post "#{base}/#{campaign.id}/recipients/retry_import", headers: headers, as: :json
    end.to have_enqueued_job(EmailCampaigns::RecipientImportJob).with(import.id)
    expect(response).to have_http_status(:accepted)
    dto = response.parsed_body.dig('payload', 'campaign')
    expect(dto.fetch('recipient_import')).to include('id' => import.id, 'status' => 'queued', 'error_code' => nil, 'retryable' => false)
    expect(import.reload).to be_queued
    expect(campaign.email_campaign_imports.count).to eq(1)

    get "#{base}/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch('payload')).to eq(dto)
  end

  [[:get, ''], [:post, ''], [:post, '/retry_import']].each do |method, suffix|
    it "preserves tenant and role authorization for #{method.upcase} recipients#{suffix}" do
      foreign = create(:email_campaign, name: 'private-foreign-campaign')
      params = method == :post ? { import_file: upload } : {}
      public_send(method, "#{base}/#{foreign.id}/recipients#{suffix}", params: params, headers: headers)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include('private-foreign-campaign')
      expect(foreign.email_campaign_imports).not_to exist

      agent = create(:user, account: account, role: :agent)
      agent_headers = agent.create_new_auth_token
      get '/api/v1/profile', headers: agent_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.fetch('id')).to eq(agent.id)
      public_send(method, "#{base}/#{campaign.id}/recipients#{suffix}", params: params, headers: agent_headers)
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body).to eq('error' => 'You are not authorized to do this action')
      expect(campaign.email_campaign_imports).not_to exist
    end
  end
end
