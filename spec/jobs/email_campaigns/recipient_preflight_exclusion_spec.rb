require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientPreflightJob do # rubocop:disable RSpec/SpecFilePathFormat -- campaign-local exclusion integration
  self.use_transactional_tests = false

  let!(:campaign) { create(:email_campaign) }
  let(:resolver) { instance_double(EmailCampaigns::Dns::MailRouteResolver) }
  let(:decision) { EmailCampaigns::PreflightDecision.new }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'true') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Dns::MailRouteResolver).to receive(:new).and_return(resolver)
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::NullStore.new)
    allow(EmailCampaigns::Ses::Client).to receive(:new).and_raise('preflight must not contact SES')
    allow(EmailCampaigns::DirectInbox::RecipientSender).to receive(:new).and_raise('preflight must not contact a provider')
    allow(EmailCampaigns::SuppressionRegistry).to receive(:new).and_raise('preflight must not write tenant suppression')
  end

  after do
    EmailCampaignImportIssue.where(email_campaign_id: campaign.id).delete_all
    campaign.destroy!
    campaign.sender_identity.destroy!
    campaign.account.destroy!
  end

  it 'excludes NXDOMAIN locally so a corrected import can send and finalize without deleting the original', :aggregate_failures do
    expect(resolver).to receive(:call).with('example.org', :MX).twice
                                      .and_return(status: :ok, records: [[10, 'mx.example.org']], ttl: 3600)
    expect(resolver).to receive(:call).with('missing.example.org', :MX).once.and_return(status: :nxdomain, ttl: 0)
    csv = "name,email\nGood,good@example.org\nBad,person@missing.example.org\n"
    EmailCampaigns::RecipientImporter.new(campaign, csv, filename: 'original.csv').perform
    expect(EmailCampaigns::Dns::MailRouteResolver).not_to have_received(:new)
    described_class.perform_now(campaign.id)
    original = campaign.email_campaign_recipients.find_by!(email: 'person@missing.example.org')
    expect(original).to be_suppressed
    expect(original.attributes).to include('preflight_status' => 'invalid', 'preflight_reason_code' => 'nxdomain')
    evidence = original.attributes
    expect(decision.campaign_allowed?(campaign)).to be true
    corrected_csv = "name,email\nGood,good@example.org\nCorrected,person@example.org\n"
    result = EmailCampaigns::RecipientImporter.new(campaign, corrected_csv, filename: 'corrected.csv').perform
    expect([result.imported, result.duplicates]).to eq([1, 1])
    corrected = campaign.email_campaign_recipients.find_by!(email: 'person@example.org')
    expect(corrected).to be_pending
    expect(corrected.preflight_status).to eq('unchecked')
    expect(decision.campaign_allowed?(campaign)).to be false
    described_class.perform_now(campaign.id)
    expect(corrected.reload.preflight_status).to eq('valid')
    expect(decision.campaign_allowed?(campaign)).to be true
    expect(original.reload.attributes).to eq(evidence)
    expect(campaign.email_campaign_recipients.count).to eq(3)
    expect(EmailSuppression.where(account: campaign.account)).to be_empty
    expect(EmailSuppressionState.where(account: campaign.account)).to be_empty
    campaign.update!(status: :sending)
    claim = EmailCampaigns::DeliveryClaim.new(campaign)
    expect(claim.claim(original)).to eq(:skipped)
    expect(claim.dispatch_allowed?(original)).to be false
    campaign.email_campaign_recipients.pending.each do |ready|
      expect(claim.claim(ready)).to eq(:claimed)
      ready.mark_sent!("synthetic-receipt-#{ready.id}")
    end
    campaign.finalize!
    expect(campaign.reload).to be_sent
    expect(campaign.suppressed_count).to eq(1)
    expect(original.reload.attributes).to eq(evidence)
  end

  %w[invalid review].each do |status|
    it "excludes a previously pending #{status} on explicit enforce recheck", :aggregate_failures do
      email = status == 'review' ? 'person@gmial.com' : 'person@missing.example.org'
      recipient = create(:email_campaign_recipient, email_campaign: campaign, email: email,
                                                    preflight_status: status, preflight_checked_at: 1.day.ago)
      if status == 'invalid'
        expect(resolver).to receive(:call).with('missing.example.org', :MX).and_return(status: :nxdomain, ttl: 0)
      else
        expect(resolver).not_to receive(:call)
      end
      perform_enqueued_jobs { expect(described_class.enqueue(campaign.id, recheck: true)).to be true }
      expect(recipient.reload).to be_suppressed
      expect(recipient.preflight_status).to eq(status)
      expect(recipient.preflight_reason_code).to eq(status == 'review' ? 'provider_typo' : 'nxdomain')
      expect(recipient.preflight_suggestion).to eq(status == 'review' ? 'person@gmail.com' : nil)
      expect(recipient.email).to eq(email)
      expect(decision.campaign_allowed?(campaign)).to be true
      expect(EmailSuppression.where(account: campaign.account)).to be_empty
      expect(EmailSuppressionState.where(account: campaign.account)).to be_empty
    end
  end

  it 'keeps DNS timeout pending and blocking both admission and finalization' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign, email: 'person@example.org')
    expect(resolver).to receive(:call).with('example.org', :MX).and_return(status: :timeout, ttl: 60)
    described_class.perform_now(campaign.id)
    expect(recipient.reload).to be_pending
    expect(recipient.preflight_status).to eq('unknown')
    expect(recipient.preflight_reason_code).to eq('dns_timeout')
    expect(decision.campaign_allowed?(campaign)).to be false
    campaign.update!(status: :sending)
    campaign.finalize!
    expect(campaign.reload).to be_sending
  end

  it 'keeps unchecked and DNS-disabled rows pending and blocking without any lookup' do
    recipient = create(:email_campaign_recipient, email_campaign: campaign, email: 'person@example.org')
    expect(decision.campaign_allowed?(campaign)).to be false
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED' => 'false') do
      expect(EmailCampaigns::Dns::MailRouteResolver).not_to receive(:new)
      described_class.perform_now(campaign.id)
    end
    expect(recipient.reload).to be_pending
    expect(recipient.preflight_status).to eq('unknown')
    expect(recipient.preflight_reason_code).to eq('dns_disabled')
    expect(decision.campaign_allowed?(campaign)).to be false
  end

  %w[shadow warning].each do |mode|
    it "keeps invalid and review rows pending and allowed in #{mode}" do
      invalid = create(:email_campaign_recipient, email_campaign: campaign, email: 'person@missing.example.org')
      review = create(:email_campaign_recipient, email_campaign: campaign, email: 'person@gmial.com')
      expect(resolver).to receive(:call).with('missing.example.org', :MX).and_return(status: :nxdomain, ttl: 0)
      with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => mode) do
        described_class.perform_now(campaign.id)
        expect(invalid.reload).to be_pending
        expect(invalid.preflight_status).to eq('invalid')
        expect(review.reload).to be_pending
        expect(review.preflight_status).to eq('review')
        expect(decision.campaign_allowed?(campaign)).to be true
        expect(decision.call(invalid)).to include(allowed: true, warning: mode == 'warning')
      end
    end
  end

  %i[claimed sent canceled newer_evidence expired_lease replaced_lease].each do |change|
    it "fences an invalid network response after #{change}" do
      recipient = create(:email_campaign_recipient, email_campaign: campaign, email: 'person@missing.example.org')
      expected = nil
      expect(resolver).to receive(:call).with('missing.example.org', :MX) do
        case change
        when :claimed then recipient.update!(status: :sent)
        when :sent then recipient.mark_sent!('synthetic-receipt')
        when :canceled then campaign.cancel!
        when :newer_evidence then recipient.update!(preflight_status: 'valid', preflight_checked_at: Time.current)
        when :expired_lease then campaign.update!(preflight_lease_expires_at: 1.second.ago)
        when :replaced_lease then campaign.update!(preflight_lease_token: SecureRandom.uuid)
        end
        expected = recipient.reload.attributes
        { status: :nxdomain, ttl: 0 }
      end
      described_class.perform_now(campaign.id)
      expect(recipient.reload.attributes).to eq(expected)
    end
  end
  it 'refreshes campaign counters when enforce excludes deterministic findings' do
    create(:email_campaign_recipient, email_campaign: campaign, email: 'person@missing.example.org')
    expect(resolver).to receive(:call).with('missing.example.org', :MX).and_return(status: :nxdomain, ttl: 0)

    described_class.perform_now(campaign.id)

    expect(campaign.reload.suppressed_count).to eq(1)
    expect(campaign.recipients_count).to eq(1)
  end
end
