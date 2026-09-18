require 'rails_helper'

RSpec.describe EmailCampaigns::UnsubscribeController, type: :controller do
  let(:campaign) { create(:email_campaign) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, status: :sent) }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:decode).with('example-token').and_return(r: recipient.id)
  end

  it 'upgrades a temporary quarantine to a permanent opt-out and deduplicates replay' do
    EmailSuppressionState.create!(account: campaign.account, email: recipient.email, active: true,
                                  reason: 'temporary_failure', expires_at: 1.hour.from_now, created_at: Time.current)
    2.times { post :create, params: { token: 'example-token' } }
    expect(response).to have_http_status(:ok)
    row = EmailSuppressionState.find_by!(account: campaign.account)
    expect(row.reason).to eq('unsubscribe')
    expect(row.expires_at).to be_nil
    expect(row.email_suppression_events.count).to eq(1)
    expect(recipient.email_events.where(event_type: :unsubscribe).count).to eq(1)
    expect(recipient.reload).to be_unsubscribed
  end

  it 'preserves a legacy long-name recipient opt-out and its permanent block on replay' do
    recipient.update_columns(name: 'N' * 300) # rubocop:disable Rails/SkipsModelValidations
    2.times { post :create, params: { token: 'example-token' } }
    expect(response).to have_http_status(:ok)
    expect(recipient.reload).to be_unsubscribed
    expect(EmailSuppression.find_by!(account: campaign.account, email: recipient.email).reason).to eq('unsubscribe')
    expect(recipient.email_events.where(event_type: :unsubscribe).count).to eq(1)
    expect(EmailSuppressionEvent.where(account: campaign.account, reason: 'unsubscribe').count).to eq(1)
  end
end
