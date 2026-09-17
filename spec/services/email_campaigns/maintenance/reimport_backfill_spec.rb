require 'rails_helper'

RSpec.describe 'Historical protection on reimport', type: :model do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:campaign) { create(:email_campaign, account: account, status: :paused) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, ses_message_id: 'old-import') }
  let(:config) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }

  %w[bounce complaint unsubscribe].each do |type|
    it "protects reimport from historical #{type}, repeated backfill and subsequent notification" do
      payload = { 'eventType' => type.capitalize, 'mail' => { 'messageId' => recipient.ses_message_id },
                  'bounce' => { 'bounceType' => 'Permanent', 'bounceSubType' => 'NoEmail' } }
      recipient.email_events.create!(event_type: type, payload: payload, occurred_at: 3.years.ago)
      2.times do |index|
        parameters = { mode: 'apply', confirm: 'apply', reason: 'Reviewed old evidence', idempotency_key: "reimport_436_#{index}" }
        run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config,
                                                      parameters: parameters)
        EmailCampaigns::Maintenance::HistoricalProtectionBackfill.new(run: run, config: config).call
      end
      event_key = type == 'unsubscribe' ? "unsubscribe:#{recipient.id}" : "ses:#{recipient.ses_message_id}:#{type}"
      expect(EmailSuppressionEvent.where(event_key: event_key).count).to eq(1)
      if type != 'unsubscribe'
        EmailCampaigns::Sns::EventProcessor.new(payload).process
        expect(EmailSuppressionEvent.where(event_key: event_key).count).to eq(1)
      end
      identity = create(:email_sender_identity, account: account, domain: 'another.example', from_email: 'sender@another.example')
      future = create(:email_campaign, account: account, sender_identity: identity, from_email: identity.from_email)
      result = EmailCampaigns::RecipientImporter.new(future, "name,email\nSynthetic,#{recipient.email}\n", filename: 'synthetic.csv').perform
      expect(result.suppressed).to eq(1)
      expect(future.email_campaign_recipients.sole).to be_suppressed
      # The old reader still sees the permanent positive after a code downgrade.
      expect(EmailSuppression.where(account_id: account.id).pluck(:email)).to include(recipient.email)
      expect(campaign.reload).to be_paused
    end
  end

  %w[Suppressed OnAccountSuppressionList OnTenantSuppressionList EmailValidationSuppressed UnsubscribedRecipient].each do |subtype|
    it "keeps #{subtype} protected in shadow when importing under another sender domain" do
      recipient.email_events.create!(event_type: :bounce, payload: {
                                       'mail' => { 'messageId' => recipient.ses_message_id },
                                       'bounce' => { 'bounceType' => 'Permanent', 'bounceSubType' => subtype }
                                     })
      parameters = { mode: 'apply', confirm: 'apply', reason: 'Synthetic provider history', idempotency_key: 'provider_reimport_436' }
      run = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config)
      identity = create(:email_sender_identity, account: account, domain: 'another.example', from_email: 'sender@another.example')
      future = create(:email_campaign, account: account, sender_identity: identity, from_email: identity.from_email)
      with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false' do
        EmailCampaigns::Maintenance::HistoricalProtectionBackfill.new(run: run, config: config).call
        result = EmailCampaigns::RecipientImporter.new(future, "name,email\nSynthetic,#{recipient.email.upcase}\n", filename: 'synthetic.csv').perform
        expect(result.suppressed).to eq(1)
        expect(future.email_campaign_recipients.sole).to be_suppressed
      end
      reason = subtype == 'UnsubscribedRecipient' ? 'unsubscribe' : 'provider_suppression'
      expect(EmailSuppression.blocking_reasons_for(account, [recipient.email])).to eq(recipient.email => reason)
    end
  end
end
