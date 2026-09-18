require 'rails_helper'

RSpec.describe 'Recipient preflight commit boundary', type: :model do
  self.use_transactional_tests = false

  let!(:campaign) { create(:email_campaign) }
  let!(:import) { campaign.email_campaign_imports.create! }

  before { allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true) }

  after do
    EmailCampaignImportIssue.where(email_campaign_id: campaign.id).delete_all
    EmailCampaignImport.where(email_campaign_id: campaign.id).delete_all
    EmailCampaignRecipient.where(email_campaign_id: campaign.id).delete_all
    campaign.destroy!
    campaign.sender_identity.destroy!
    campaign.account.destroy!
  end

  it 'enqueues only after atomic import commit and resolves each domain outside transactions' do
    resolver = instance_double(EmailCampaigns::Dns::MailRouteResolver)
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'true') do
      expect(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue).with(campaign.id) do
        expect(ActiveRecord::Base.connection.transaction_open?).to be false
      end
      allow(EmailCampaigns::Dns::MailRouteResolver).to receive(:new) do
        raise 'DNS constructed during import'
      end
      EmailCampaignImport.transaction do
        csv = "name,email\nOne,one@example.org\nTwo,two@example.org\n"
        EmailCampaigns::RecipientImporter.new(campaign, csv, filename: 'list.csv', import: import).perform
        import.update!(status: :completed)
      end
      allow(EmailCampaigns::Dns::MailRouteResolver).to receive(:new).and_return(resolver)
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)
      expect(resolver).to receive(:call).with('example.org', :MX).once do
        expect(ActiveRecord::Base.connection.transaction_open?).to be false
        { status: :ok, records: [[10, 'mx.example.org']], ttl: 60 }
      end
      EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id)
      expect(campaign.email_campaign_recipients.pluck(:preflight_status)).to eq(%w[valid valid])
      EmailCampaigns::RecipientPreflightJob.perform_now(campaign.id)
    end
  end

  it 'reconciles a lost post-commit enqueue from the durable unchecked recipients' do
    create(:email_campaign_recipient, email_campaign: campaign)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue).and_return(false)
    import.update!(status: :completed)
    allow(EmailCampaigns::RecipientPreflightJob).to receive(:enqueue).and_call_original
    clear_enqueued_jobs
    expect do
      EmailCampaigns::RecipientImportMaintenanceJob.perform_now
    end.to have_enqueued_job(EmailCampaigns::RecipientPreflightJob).with(campaign.id, an_instance_of(String), 0)
  end
end
