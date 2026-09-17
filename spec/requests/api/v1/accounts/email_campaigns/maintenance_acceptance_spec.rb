require 'rails_helper'

# One HTTP lifecycle per example: assert every boundary without replaying its mutations.
# rubocop:disable RSpec/MultipleExpectations
RSpec.describe 'Account maintenance acceptance', type: :request do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin') }
  let(:headers) { actor.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/maintenance/backfills" }
  let(:input) { { reason: 'Synthetic acceptance', idempotency_key: 'acceptance_preview_436' } }
  let(:campaign) { create(:email_campaign, account: account, status: :paused) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, email: 'protected@example.org', ses_message_id: 'synthetic-436') }
  let(:identity) { create(:email_sender_identity, account: account, domain: 'future.example', from_email: 'sender@future.example') }
  let(:future) { create(:email_campaign, account: account, sender_identity: identity, from_email: identity.from_email, status: :sending) }

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true', EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow',
                      EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false', EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED: 'true',
                      EMAIL_REPUTATION_MODE: 'shadow', EMAIL_REPUTATION_PROVIDER_MONITOR: 'false', EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  it 'previews then applies historical provider prevention and blocks a future list under another sender domain with zero dispatch' do
    historical = recipient.email_events.create!(event_type: :complaint, occurred_at: 3.years.ago, payload: {
                                                  'mail' => { 'messageId' => 'synthetic-436' },
                                                  'complaint' => { 'complaintSubType' => 'OnTenantSuppressionList', 'private' => 'raw-private-value' }
                                                })
    before = [campaign.reload.attributes, recipient.reload.attributes, historical.reload.attributes]
    expect(EmailCampaigns::Ses::Client).not_to receive(:new)
    expect(EmailCampaigns::DeliveryJob).not_to receive(:perform_later)
    post path, params: input, headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    preview = EmailProtectionMaintenanceRun.find(response.parsed_body.fetch('id'))
    2.times { EmailCampaigns::ProtectionBackfillJob.perform_now(preview.id) }
    expect(preview.reload).to have_attributes(status: 'completed', dry_run: true)
    expect(EmailSuppressionState.count).to eq(0)
    expect(EmailSuppressionEvent.count).to eq(0)
    expect(EmailSuppression.count).to eq(0)
    post path, params: input.merge(mode: 'apply', confirm: 'apply', idempotency_key: 'acceptance_apply_436'), headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    applied = EmailProtectionMaintenanceRun.find(response.parsed_body.fetch('id'))
    messages = []
    notifications = []
    allow(Rails.logger).to receive(:info) { |message| messages << message }
    subscription = ActiveSupport::Notifications.subscribe(/email_protection\./) { |*args| notifications << args.last }
    2.times { EmailCampaigns::ProtectionBackfillJob.perform_now(applied.id) }
    expect(applied.reload).to have_attributes(status: 'completed', dry_run: false)
    expect(applied.counts['eligible_events']).to eq(preview.counts['eligible_events'])
    result = EmailCampaigns::RecipientImporter.new(future, "name,email\nSynthetic,PROTECTED@EXAMPLE.ORG\n", filename: 'synthetic.csv').perform
    expect(result.suppressed).to eq(1)
    expect(future.email_campaign_recipients.sole).to be_suppressed
    expect(EmailCampaigns::DeliveryClaim.new(future).claim(future.email_campaign_recipients.sole)).to eq(:skipped)
    expect([campaign.reload.attributes, recipient.reload.attributes, historical.reload.attributes]).to eq(before)
    expect(EmailSuppression.sole.reason).to eq('provider_suppression')
    audit = EmailSuppressionEvent.sole
    expect(audit).to have_attributes(source: 'backfill', reason: 'provider_suppression', occurred_at: historical.occurred_at)
    expect(audit.metadata).to include('historical_event_id' => historical.id, 'maintenance_run_id' => applied.id)
    expect(notifications).not_to be_empty
    serialized = [messages, notifications, applied.public_progress, audit.metadata].to_json
    expect(serialized).not_to include(recipient.email, 'raw-private-value', 'synthetic-436', input[:reason], input[:idempotency_key])
  ensure
    ActiveSupport::Notifications.unsubscribe(subscription) if subscription
  end

  it 'keeps account history and the independent global provider latch unchanged through status, apply and retry' do
    account.update!(internal_attributes: { EmailCampaigns::Guardrail::FLAG_KEY => { 'reason' => 'historical_pause' } })
    state = EmailReputationState.create!(account: account, blocked: true, level: 'paused', triggered_at: 2.days.ago,
                                         trigger_snapshot: { 'evidence' => 'synthetic historical trigger' })
    provider = EmailProviderState.create!(provider_key: EmailCampaigns::Reputation::ProviderConfig.new.provider_key,
                                          status: 'blocked', blocked: true, manual_block: true, observed_at: 1.day.ago)
    audit = EmailReputationAudit.create!(account_id: account.id, action: 'paused', snapshot: { 'evidence' => 'retained' })
    recipient.email_events.create!(event_type: :unsubscribe)
    before = [account.reload.attributes, campaign.reload.attributes, recipient.reload.attributes, state.attributes, provider.attributes,
              audit.attributes]
    expect(EmailCampaigns::Ses::Client).not_to receive(:new)
    post path, params: input.merge(mode: 'apply', confirm: 'apply'), headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    run = EmailProtectionMaintenanceRun.find(response.parsed_body.fetch('id'))
    run.fail_run!('batch_failed')
    get "#{path}/#{run.id}", headers: headers
    expect(response).to have_http_status(:ok)
    post "#{path}/#{run.id}/retry", headers: headers, as: :json
    expect(response).to have_http_status(:accepted)
    2.times { EmailCampaigns::ProtectionBackfillJob.perform_now(run.id) }
    expect(run.reload.status).to eq('completed')
    expect([account.reload.attributes, campaign.reload.attributes, recipient.reload.attributes,
            state.reload.attributes, provider.reload.attributes, audit.reload.attributes]).to eq(before)
    expect(EmailSuppression.sole.reason).to eq('unsubscribe')
    expect(EmailCampaigns::Guardrail.paused?(account)).to be(true)
    expect(EmailCampaigns::Reputation::ProviderGate.protection).to include(code: 'provider_manual_block')
    foreign = create(:account)
    expect(EmailSuppression.suppressed?(foreign, recipient.email)).to be(false)
    expect(EmailCampaigns::Guardrail.protection(foreign)).to include(kind: 'provider', overridable: false)
  end
end

# rubocop:enable RSpec/MultipleExpectations
