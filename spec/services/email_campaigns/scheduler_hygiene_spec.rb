require 'rails_helper'

RSpec.describe EmailCampaigns::Scheduler do
  let(:campaign) { create(:email_campaign, status: :scheduled, scheduled_at: 1.minute.ago) }
  let!(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }

  before { allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true) }

  it 'pauses a due enforce campaign with unresolved validation, without claiming completion or delivery' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce') do
      expect { described_class.new.perform }.not_to have_enqueued_job(EmailCampaigns::DeliveryJob)
      expect(campaign.reload).to be_paused
      expect(campaign.hygiene_pause_reason).to eq('hygiene_validation_required')
      expect(recipient.reload).to be_pending
    end
  end

  it 'preserves shadow sendability and does not run DNS in the scheduler transaction' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'shadow') do
      expect(EmailCampaigns::Dns::MailRouteResolver).not_to receive(:new)
      expect { described_class.new.perform }.to have_enqueued_job(EmailCampaigns::DeliveryJob).with(campaign.id)
      expect(campaign.reload).to be_sending
    end
  end

  it 'does not overtake an active import' do
    campaign.email_campaign_imports.create!(status: :processing)
    expect { described_class.new.perform }.not_to have_enqueued_job(EmailCampaigns::DeliveryJob)
    expect(campaign.reload).to be_scheduled
  end
end
