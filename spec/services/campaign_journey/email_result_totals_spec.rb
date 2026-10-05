require 'rails_helper'

# #999, acceptance E1 (e-mail): Entregues + Voltaram + Não enviados = Público elegível.
RSpec.describe CampaignJourney::EmailResultTotals, :aggregate_failures do
  let(:campaign) { create(:email_campaign, status: :sent) }

  it 'puts every recipient in exactly one group' do
    sent_states = { sent: 1, delivered: 1, opened: 1, clicked: 1, unsubscribed: 1, complained: 1 }
    sent_states.each { |status, n| create_list(:email_campaign_recipient, n, email_campaign: campaign, status: status, sent_at: 1.hour.ago) }
    create_list(:email_campaign_recipient, 2, email_campaign: campaign, status: :bounced, sent_at: 1.hour.ago)
    create(:email_campaign_recipient, email_campaign: campaign, status: :suppressed)
    create(:email_campaign_recipient, email_campaign: campaign, status: :failed)
    create(:email_campaign_recipient, email_campaign: campaign, status: :pending)

    totals = described_class.new(campaign).call

    expect(totals).to eq(eligible: 11, delivered: 6, bounced: 2, not_sent: 3)
    expect(totals[:delivered] + totals[:bounced] + totals[:not_sent]).to eq(totals[:eligible])
  end
end
