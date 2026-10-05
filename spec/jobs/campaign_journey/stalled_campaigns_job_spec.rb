require 'rails_helper'

# #1005 M2: a linked campaign stuck in processing is closed with every queued recipient failed.
RSpec.describe CampaignJourney::StalledCampaignsJob, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:channel) { journey_cloud_channel(account) }
  let(:audience) { saved_audience(account: account, user: account_and_user.last, content: "Nome,Celular\nAna,11987654321\nBia,21987654321\n") }

  def processing_campaign(started_at:, linked: true)
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params)
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[:processing], started_at: started_at) # rubocop:disable Rails/SkipsModelValidations
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience) if linked
    audience.campaign_import_rows.each_with_index do |row, index|
      CampaignRecipient.create!(account: account, campaign: campaign, contact_id: row.contact_id, inbox: channel.inbox,
                                status: index.zero? ? :sent : :queued, updated_at: started_at, created_at: started_at)
    end
    campaign
  end

  it 'fails the queued recipients of a stalled linked campaign and completes it' do
    stalled = processing_campaign(started_at: 3.hours.ago)
    recent = processing_campaign(started_at: 10.minutes.ago)
    unlinked = processing_campaign(started_at: 3.hours.ago, linked: false)

    described_class.perform_now

    expect(stalled.reload).to be_completed
    expect(CampaignRecipient.where(campaign: stalled).pluck(:status, :error_message))
      .to contain_exactly(['sent', nil], ['failed', CampaignJourney::StalledCampaignsJob::REASON])
    expect(recent.reload).to be_processing
    expect(unlinked.reload).to be_processing
  end

  it 'leaves alone a campaign whose recipients are still moving' do
    campaign = processing_campaign(started_at: 3.hours.ago)
    CampaignRecipient.where(campaign: campaign).sent.update_all(updated_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.perform_now

    expect(campaign.reload).to be_processing
  end
end
