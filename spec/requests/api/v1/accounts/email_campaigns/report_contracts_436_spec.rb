require 'rails_helper'

RSpec.describe 'Email campaign public report contracts #436', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/email_campaigns" }
  let(:campaign) { create(:email_campaign, account: account, status: :sending) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_REPUTATION_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  it 'exposes the actual persisted hygiene pause across campaign and report views' do
    EmailCampaigns::PreflightDecision.new.pause!(campaign)
    expect(campaign.reload).to be_paused
    expect(campaign.pause_reason).to eq({})
    expect(campaign.hygiene_pause_reason).to eq('hygiene_validation_required')

    get "#{base}/campaigns/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'pause_reason')).to eq('preflight_review')
    get "#{base}/campaigns", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaigns').sole.fetch('pause_reason')).to eq('preflight_review')
    get "#{base}/campaigns/#{campaign.id}/recipients", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaign', 'pause_reason')).to eq('preflight_review')
    get "#{base}/reports", params: { campaign_id: campaign.id }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'campaigns').sole.fetch('pause_reason')).to eq('preflight_review')
    get "#{base}/reports/#{campaign.id}", headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'pause_reason')).to eq('preflight_review')
  end

  context 'with one accepted SES permanent bounce and three accepted direct recipients' do
    let(:direct) do
      inbox = create(:inbox, :with_email, account: account)
      create(:email_campaign, account: account, delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    end

    before do
      ses = create(:email_campaign_recipient, email_campaign: campaign, status: :bounced, sent_at: 1.hour.ago)
      ses.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'General' } })
      create_list(:email_campaign_recipient, 3, email_campaign: direct, status: :sent, sent_at: 1.hour.ago)
    end

    [[:all, 4, 1, 3], [:ses, 1, 1, 0], [:direct, 3, 0, 3]].each do |selection, sent, ses_sent, excluded|
      it "preserves explicit denominators in the #{selection} report, its campaign rows and detail" do
        selected = { ses: campaign, direct: direct }[selection]
        filters = selected ? { campaign_id: selected.id } : {}
        get "#{base}/reports", params: filters, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        payload = response.parsed_body.fetch('payload')
        summary = payload.fetch('summary')
        rate = ses_sent.positive? ? 100.0 : nil
        status = ses_sent.positive? ? 'available' : 'no_data'
        expect(summary).to include('sent' => sent, 'hard_bounce_rate' => rate)
        expect(summary.dig('rates', 'hard_bounce_rate')).to eq(rate)
        expect(summary.dig('rate_metadata', 'hard_bounce_rate')).to eq(
          'value' => rate, 'numerator' => ses_sent, 'denominator' => ses_sent, 'basis' => 'ses_accepted_recipients', 'status' => status
        )
        expect(summary.dig('rate_metadata', 'bounce_rate')).to include('denominator' => sent, 'basis' => 'accepted_recipients')
        expect(summary.fetch('reputation_coverage')).to include(
          'sent' => ses_sent, 'excluded_direct_sent' => excluded, 'hard_bounce_rate' => rate,
          'scope' => 'selected_ses_campaigns', 'accepted_basis' => 'recipient_sent_at', 'official_ses_ratio' => false, 'status' => status
        )
        rows = payload.fetch('campaigns')
        expect(rows.pluck('id')).to match_array(selected ? [selected.id] : [campaign.id, direct.id])
        expect(rows.sole.slice('rate_metadata', 'reputation_coverage')).to eq(summary.slice('rate_metadata', 'reputation_coverage')) if selected
        rows.each do |row|
          get "#{base}/reports/#{row.fetch('id')}", headers: headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body.fetch('payload').slice('rate_metadata', 'reputation_coverage')).to eq(
            row.slice('rate_metadata', 'reputation_coverage')
          )
        end
      end
    end
  end
end
