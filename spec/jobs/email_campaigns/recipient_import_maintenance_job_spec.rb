require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientImportMaintenanceJob do
  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    clear_enqueued_jobs
  end

  it 'isolates a deleted DirectInbox sender while preserving other preflights, recovery and file retention' do
    inbox = create(:inbox, :with_email)
    broken = create(:email_campaign, account: inbox.account, delivery_mode: :direct_inbox, sender_inbox: inbox, sender_identity: nil)
    create(:email_campaign_recipient, email_campaign: broken)
    # Delete the referenced row directly to exercise the actual ON DELETE SET NULL FK.
    inbox.delete
    healthy = create(:email_campaign)
    create(:email_campaign_recipient, email_campaign: healthy)
    recoverable = create(:email_campaign).email_campaign_imports.create!(updated_at: 11.minutes.ago)
    expired = create(:email_campaign).email_campaign_imports.create!(status: :failed, created_at: 2.days.ago)
    expired.source_file.attach(io: StringIO.new("name,email\n"), filename: 'expired.csv', content_type: 'text/csv')
    expect(broken.reload.sender_inbox_id).to be_nil
    expect(Rails.logger).to receive(:error).with(
      { event: 'email_campaign_preflight_enqueue_failed', campaign_id: broken.id, error_class: 'ActiveRecord::RecordInvalid' }.to_json
    )
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'shadow', 'EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      expect { described_class.perform_now }.not_to raise_error
    end
    expect(enqueued_jobs.select { |job| job[:job] == EmailCampaigns::RecipientPreflightJob }.pluck(:args).map(&:first)).to include(healthy.id)
    expect(EmailCampaigns::RecipientImportJob).to have_been_enqueued.with(recoverable.id)
    expect(ActiveStorage::PurgeJob).to have_been_enqueued
  end

  it 'attempts existing housekeeping but propagates a global preflight database failure' do
    job = described_class.new
    recoverable = create(:email_campaign).email_campaign_imports.create!(updated_at: 11.minutes.ago)
    allow(job).to receive(:enqueue_preflights).and_raise(ActiveRecord::ConnectionNotEstablished, 'database unavailable')
    expect { job.perform }.to(raise_error { |error| expect(error.class.name).to eq('ActiveRecord::ConnectionNotEstablished') })
    expect(EmailCampaigns::RecipientImportJob).to have_been_enqueued.with(recoverable.id)
  end
end
