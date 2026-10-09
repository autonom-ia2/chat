require 'rails_helper'

RSpec.describe EmailCampaigns::PreflightDecision do
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }

  statuses = %w[unchecked invalid review unknown valid]
  %w[shadow warning enforce].each do |mode|
    statuses.each do |status|
      it "handles #{status} in #{mode}" do
        recipient.update!(preflight_status: status, preflight_valid_until: 1.hour.from_now)
        config = EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => mode)
        result = described_class.new(config: config).call(recipient)
        expect(result[:allowed]).to eq(mode != 'enforce' || status == 'valid')
        expect(result[:warning]).to eq(mode == 'warning' && status != 'valid')
      end
    end
  end

  it 'refuses expired valid outcomes and does not overwrite a manual pause' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.second.ago)
    decision = described_class.new(config: EmailCampaigns::HygieneConfig.new('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce'))
    expect(decision.call(recipient)[:allowed]).to be false
    campaign.update!(status: :paused, last_error: 'manual pause', hygiene_pause_reason: nil)
    decision.pause!(campaign)
    expect(campaign.reload.last_error).to eq('manual pause')
    expect(campaign.hygiene_pause_reason).to be_nil
  end

  it 'does not finalize unresolved pending recipients, even in shadow' do
    recipient
    campaign.finalize!
    expect(campaign.reload).to be_sending
  end
end
