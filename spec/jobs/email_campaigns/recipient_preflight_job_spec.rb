require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientPreflightJob do
  let(:campaign) { create(:email_campaign) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, email: 'test@gmial.com') }

  before { allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true) }

  it 'records review outcomes without DNS by default and repeats idempotently' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      recipient
      expect(EmailCampaigns::Dns::MailRouteResolver).not_to receive(:new)
      described_class.perform_now(campaign.id)
      expect(recipient.reload.preflight_status).to eq('review')
      expect(recipient.preflight_suggestion).to eq('test@gmail.com')
      checked_at = recipient.preflight_checked_at
      described_class.perform_now(campaign.id)
      expect(recipient.reload.preflight_checked_at).to eq(checked_at)
      expect(campaign.reload.preflight_summary).to eq('review' => 1)
      expect(EmailSuppression.where(account: campaign.account)).to be_empty
    end
  end

  it 'refuses DNS inside an open transaction before constructing the resolver' do
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'true') do
      recipient
      expect(EmailCampaigns::Dns::MailRouteResolver).not_to receive(:new)
      expect { described_class.new.perform(campaign.id) }.to raise_error(/outside a database transaction/)
    end
  end

  it 'leaves already dispatched history and manual pauses untouched' do
    recipient.update!(status: :sent)
    campaign.update!(status: :paused, last_error: 'tenant pause')
    described_class.perform_now(campaign.id)
    expect(recipient.reload.preflight_status).to eq('unchecked')
    expect(recipient).to be_sent
    expect(campaign.reload).to be_paused
    expect(campaign.last_error).to eq('tenant pause')
  end

  it 'defers until the atomic import completes' do
    recipient
    campaign.email_campaign_imports.create!(status: :processing)
    described_class.perform_now(campaign.id)
    expect(recipient.reload.preflight_status).to eq('unchecked')
  end

  it 'bounds work and schedules a continuation for unchecked recipients' do
    create_list(:email_campaign_recipient, 101, email_campaign: campaign)
    last_id = campaign.email_campaign_recipients.order(:id).offset(99).first.id
    expect { described_class.perform_now(campaign.id) }.to have_enqueued_job(described_class).with(campaign.id, an_instance_of(String), last_id)
    expect(campaign.email_campaign_recipients.where(preflight_status: 'unchecked').count).to eq(1)
  end
end
