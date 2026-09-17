require 'rails_helper'

RSpec.describe EmailCampaigns::Maintenance::HistoricalProtectionBackfill do
  let(:account) { create(:account) }
  let(:suppression_events) { EmailSuppressionEvent.where(account_id: account.id) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:campaign) { create(:email_campaign, account: account, status: :paused) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, ses_message_id: 'historical-message') }
  let(:config) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }
  let(:parameters) { { mode: 'apply', confirm: 'apply', reason: 'epic436 reviewed evidence', idempotency_key: 'epic436_historical_01' } }
  let(:run) { EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config) }
  let(:payload) do
    { 'mail' => { 'messageId' => recipient.ses_message_id }, 'bounce' => { 'bounceType' => 'Permanent', 'bounceSubType' => 'NoEmail' } }
  end

  it 'previews real events without changing protection, recipients or campaign state' do
    recipient.email_events.create!(event_type: :bounce, payload: payload)
    parameters[:mode] = 'dry_run'
    parameters.delete(:confirm)
    before = [recipient.reload.attributes, campaign.reload.attributes]
    expect(Mail).not_to receive(:new)
    expect(EmailCampaigns::Ses::Client).not_to receive(:new)
    described_class.new(run: run, config: config).call
    expect(run.reload.counts).to include('events_processed' => 1, 'eligible_events' => 1, 'unprotected_candidate_events' => 1)
    expect(EmailSuppression.count).to eq(0)
    expect(EmailSuppressionState.count).to eq(0)
    expect(suppression_events.count).to eq(0)
    expect([recipient.reload.attributes, campaign.reload.attributes]).to eq(before)
  end

  [
    %w[Permanent NoEmail eligible_events], %w[Permanent General eligible_events],
    %w[Transient MailboxFull skipped_temporary_events], %w[Undetermined Undetermined skipped_unknown_events],
    %w[Permanent OnAccountSuppressionList eligible_events], %w[Permanent Suppressed eligible_events],
    %w[Permanent OnTenantSuppressionList eligible_events], %w[Permanent EmailValidationSuppressed eligible_events],
    %w[Permanent UnsubscribedRecipient eligible_events]
  ].each do |type, subtype, counter|
    it "classifies historical #{type}/#{subtype} from actual payload" do
      payload['bounce'] = { 'bounceType' => type, 'bounceSubType' => subtype }
      recipient.email_events.create!(event_type: :bounce, payload: payload)
      preview_input = parameters.except(:mode, :confirm).merge(idempotency_key: 'bounce_preview_436')
      preview = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config, parameters: preview_input)
      described_class.new(run: preview, config: config).call
      expect(preview.reload.counts[counter]).to eq(1)
      expect([EmailSuppression.count, EmailSuppressionState.count, suppression_events.count]).to eq([0, 0, 0])
      described_class.new(run: run, config: config).call
      expect(run.reload.counts.slice('eligible_events', 'skipped_temporary_events', 'skipped_unknown_events'))
        .to eq(preview.counts.slice('eligible_events', 'skipped_temporary_events', 'skipped_unknown_events'))
      expect(EmailSuppression.suppressed?(account, recipient.email)).to eq(counter == 'eligible_events')
    end
  end

  {
    'NoEmail' => %w[permanent permanent_failure hard_bounce],
    'Suppressed' => %w[permanent provider_suppression provider_suppression],
    'OnAccountSuppressionList' => %w[unknown provider_suppression provider_suppression],
    'OnTenantSuppressionList' => %w[unknown provider_suppression provider_suppression],
    'EmailValidationSuppressed' => %w[unknown provider_suppression provider_suppression],
    'UnsubscribedRecipient' => %w[unknown unsubscribe unsubscribe]
  }.each do |subtype, (classification, reason_code, reason)|
    it "preserves the origin and durable block for #{subtype} without inventing an invalid mailbox" do
      payload['bounce']['bounceSubType'] = subtype
      historical = recipient.email_events.create!(event_type: :bounce, payload: payload)
      before = historical.attributes
      described_class.new(run: run, config: config).call
      expect(EmailSuppressionState.sole).to have_attributes(active: true, reason: reason, expires_at: nil)
      expect(EmailSuppression.sole.reason).to eq(reason)
      audit = suppression_events.sole
      expect(audit.reason).to eq(reason)
      expect(audit.metadata).to eq('historical_event_id' => historical.id, 'maintenance_run_id' => run.id,
                                   'classification' => classification, 'reason_code' => reason_code)
      expect(historical.reload.attributes).to eq(before)
      result = EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email).block!(
        reason: reason, source: 'ses', event_key: "ses:#{recipient.ses_message_id}:bounce"
      )
      expect(result.duplicate).to be(true)
      expect(suppression_events.count).to eq(1)
    end
  end

  it 'mirrors legacy provider suppression without promoting it above a later hard bounce' do
    legacy = EmailSuppression.create!(account: account, email: recipient.email, reason: 'provider_suppression', created_at: 3.years.ago)
    described_class.new(run: run, config: config).call
    described_class.new(run: run.reload, config: config).call
    expect(suppression_events.sole).to have_attributes(reason: 'provider_suppression',
                                                       occurred_at: legacy.created_at)
    expect(EmailSuppressionState.sole.reason).to eq('provider_suppression')
    EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email).block!(
      reason: 'hard_bounce', source: 'ses', event_key: 'ses:later:bounce'
    )
    expect(EmailSuppressionState.sole.reason).to eq('hard_bounce')
    expect(legacy.reload.reason).to eq('hard_bounce')
  end

  it 'does not lower consent or spam priority when older provider prevention arrives later' do
    recipient.email_events.create!(event_type: :unsubscribe)
    recipient.email_events.create!(event_type: :complaint)
    payload['bounce']['bounceSubType'] = 'Suppressed'
    recipient.email_events.create!(event_type: :bounce, payload: payload, occurred_at: 3.years.ago)
    described_class.new(run: run, config: config).call
    expect(EmailSuppressionState.sole.reason).to eq('unsubscribe')
    expect(EmailSuppression.sole.reason).to eq('unsubscribe')
    expect(suppression_events.order(:id).pluck(:reason)).to eq(%w[unsubscribe complaint provider_suppression])
  end

  %w[hard_bounce complaint unsubscribe].each do |reason|
    it "preserves existing #{reason} when historical provider suppression is replayed" do
      EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email).block!(
        reason: reason, source: 'ses', event_key: "existing:#{reason}"
      )
      payload['bounce']['bounceSubType'] = 'OnAccountSuppressionList'
      recipient.email_events.create!(event_type: :bounce, payload: payload)
      described_class.new(run: run, config: config).call
      described_class.new(run: run.reload, config: config).call
      expect(EmailSuppressionState.sole).to have_attributes(reason: reason, active: true, expires_at: nil)
      expect(EmailSuppression.sole.reason).to eq(reason)
      expect(suppression_events.where(reason: 'provider_suppression').count).to eq(1)
    end
  end

  it 'does not invent hard bounce from status or a payloadless event and never replays soft counts' do
    recipient.update!(status: :bounced)
    recipient.email_events.create!(event_type: :bounce, payload: {})
    3.times { recipient.email_events.create!(event_type: :bounce, payload: { 'bounce' => { 'bounceType' => 'Transient' } }) }
    described_class.new(run: run, config: config).call
    expect(run.reload.counts).to include('skipped_unknown_events' => 1, 'skipped_temporary_events' => 3)
    expect(EmailSuppressionState.count).to eq(0)
    expect(suppression_events.count).to eq(0)
  end

  it 'keeps permanent, spam and unsubscribe evidence across reimport without changing paused campaign or recipients' do
    recipient.email_events.create!(event_type: :unsubscribe)
    recipient.email_events.create!(event_type: :complaint, payload: { 'mail' => { 'messageId' => recipient.ses_message_id } })
    recipient.email_events.create!(event_type: :bounce, payload: payload)
    before = [campaign.reload.attributes, recipient.reload.attributes]
    described_class.new(run: run, config: config).call
    future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity)
    imported = create(:email_campaign_recipient, email_campaign: future, email: recipient.email)
    expect(EmailSuppression.blocking_reasons_for(account, [imported.email])).to eq(imported.email => 'unsubscribe')
    expect(EmailSuppressionState.find_by!(account: account, email: imported.email).reason).to eq('unsubscribe')
    expect(run.reload.counts).to include('eligible_events' => 3, 'block_records_created' => 3, 'already_protected_events' => 2)
    expect([campaign.reload.attributes, recipient.reload.attributes]).to eq(before)
  end

  it 'deduplicates repeated historical and subsequent live registry notifications with the same key' do
    2.times { recipient.email_events.create!(event_type: :bounce, payload: payload) }
    described_class.new(run: run, config: config).call
    result = EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email, campaign: campaign).block!(
      reason: 'hard_bounce', source: 'ses', event_key: "ses:#{recipient.ses_message_id}:bounce"
    )
    expect(result.duplicate).to be(true)
    expect(suppression_events.count).to eq(1)
    expect(run.reload.counts).to include('events_processed' => 2, 'eligible_events' => 2,
                                         'block_records_created' => 1, 'duplicate_events' => 1, 'already_protected_events' => 1)
  end

  it 'counts two different events for one address as events, preserving strong priority out of order' do
    recipient.email_events.create!(event_type: :complaint, occurred_at: 1.day.ago)
    recipient.email_events.create!(event_type: :bounce, occurred_at: 2.days.ago, payload: payload)
    described_class.new(run: run, config: config).call
    expect(run.reload.counts).to include('eligible_events' => 2, 'block_records_created' => 2, 'already_protected_events' => 1)
    expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq('complaint')
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email).reason).to eq('complaint')
  end

  it 'retains legacy reason and creation time, bounding arbitrary historical proof' do
    legacy = EmailSuppression.create!(account: account, email: recipient.email, reason: 'old private free text', created_at: 3.years.ago)
    original = legacy.attributes
    described_class.new(run: run, config: config).call
    described_class.new(run: run.reload, config: config).call
    event = suppression_events.sole
    expect(legacy.reload.attributes).to eq(original)
    expect(event).to have_attributes(reason: 'manual', source: 'backfill', occurred_at: legacy.created_at)
    expect(event.metadata).to include('evidence_code' => 'legacy_permanent_positive')
    expect(event.metadata.to_json).not_to include('old private free text')
    expect(EmailSuppression.suppressed?(account, recipient.email)).to be(true)
  end

  it 'does not downgrade an existing stronger state while mirroring legacy positives' do
    legacy = EmailSuppression.create!(account: account, email: recipient.email, reason: 'hard_bounce', created_at: 2.years.ago)
    state = EmailSuppressionState.create!(account: account, email: recipient.email, active: true, reason: 'unsubscribe')
    described_class.new(run: run, config: config).call
    described_class.new(run: run.reload, config: config).call
    expect(state.reload.reason).to eq('unsubscribe')
    expect(legacy.reload.reason).to eq('hard_bounce')
    expect(suppression_events.sole.occurred_at).to eq(legacy.created_at)
  end

  it 'excludes foreign account evidence and checks account ownership again when constructing proof' do
    foreign = create(:email_campaign_recipient)
    event = foreign.email_events.create!(event_type: :complaint)
    recipient.email_events.create!(event_type: :unsubscribe)
    described_class.new(run: run, config: config).call
    expect(run.reload.counts['events_processed']).to eq(1)
    expect(EmailSuppression.where(account_id: foreign.email_campaign.account_id)).to be_empty
    expect { EmailCampaigns::Maintenance::Evidence.new(event, account_id: account.id) }.to raise_error(ArgumentError, 'account_mismatch')
  end

  it 'does not disclose email, payload, operator reason or idempotency key in progress or structured logs' do
    recipient.email_events.create!(event_type: :bounce, payload: payload.merge('private' => 'provider-secret'))
    messages = []
    allow(Rails.logger).to receive(:info) { |message| messages << message }
    described_class.new(run: run, config: config).call
    serialized = [run.reload.public_progress.to_json, *messages].join
    expect(serialized).not_to include(recipient.email, 'provider-secret', parameters[:reason], parameters[:idempotency_key], 'historical-message')
    expect(messages.join).to include('email_protection.batch_finished')
    expect(suppression_events.sole.metadata.to_json).not_to include(parameters[:reason],
                                                                    parameters[:idempotency_key], 'provider-secret')
  end

  it 'preserves the account guardrail, manual campaign pause and disabled global sending' do
    account.update!(internal_attributes: { EmailCampaigns::Guardrail::FLAG_KEY => { 'reason' => 'manual_review' } })
    recipient.email_events.create!(event_type: :unsubscribe)
    before = account.reload.attributes
    with_modified_env EMAIL_CAMPAIGN_ENABLED: 'false' do
      described_class.new(run: run, config: config).call
      expect(EmailCampaigns::Config.enabled?).to be(false)
    end
    expect(account.reload.attributes).to eq(before)
    expect(EmailCampaigns::Guardrail.paused?(account)).to be(true)
    expect(campaign.reload).to be_paused
    expect(EmailSuppression.suppressed?(account, recipient.email)).to be(true)
  end

  %w[OnAccountSuppressionList OnTenantSuppressionList].each do |subtype|
    it "classifies Complaint/#{subtype} identically in preview and apply without creating new spam" do
      historical = recipient.email_events.create!(event_type: :complaint, occurred_at: 3.years.ago, payload: {
                                                    'mail' => { 'messageId' => recipient.ses_message_id },
                                                    'complaint' => { 'complaintSubType' => subtype, 'private' => recipient.email }
                                                  })
      preview_input = parameters.except(:mode, :confirm).merge(idempotency_key: 'complaint_preview_436')
      preview = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config, parameters: preview_input)
      described_class.new(run: preview, config: config).call
      expect(preview.reload.counts['eligible_events']).to eq(1)
      expect(suppression_events.count).to eq(0)
      described_class.new(run: run, config: config).call
      expect(run.reload.counts['eligible_events']).to eq(preview.counts['eligible_events'])
      expect(EmailSuppressionState.sole).to have_attributes(reason: 'provider_suppression', active: true, expires_at: nil)
      expect(EmailSuppression.sole.reason).to eq('provider_suppression')
      expect(suppression_events.sole).to have_attributes(reason: 'provider_suppression', source: 'backfill',
                                                         occurred_at: historical.occurred_at, event_key: 'ses:historical-message:complaint')
      expect(suppression_events.sole.metadata).to eq('reason_code' => 'provider_suppression',
                                                     'historical_event_id' => historical.id, 'maintenance_run_id' => run.id)
    end
  end

  it 'retains unsubscribe when a provider-prevented Complaint arrives later' do
    recipient.email_events.create!(event_type: :unsubscribe)
    recipient.email_events.create!(event_type: :complaint, payload: { 'complaint' => { 'complaintSubType' => 'OnAccountSuppressionList' } })
    described_class.new(run: run, config: config).call
    expect(EmailSuppressionState.sole.reason).to eq('unsubscribe')
    expect(EmailSuppression.sole.reason).to eq('unsubscribe')
    expect(suppression_events.order(:id).pluck(:reason)).to eq(%w[unsubscribe provider_suppression])
  end

  it 'retains active quarantine when historical temporary evidence is replayed after a behavioral rollback to shadow' do
    state = EmailSuppressionState.create!(account: account, email: recipient.email, active: true,
                                          reason: 'temporary_failure', expires_at: 2.days.from_now)
    recipient.email_events.create!(event_type: :bounce, payload: { 'bounce' => { 'bounceType' => 'Transient' } })
    original = state.attributes
    with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_REPUTATION_MODE: 'shadow' do
      described_class.new(run: run, config: config).call
    end
    expect(state.reload.attributes).to eq(original)
    expect(run.reload.counts['skipped_temporary_events']).to eq(1)
    expect(suppression_events.count).to eq(0)
  end
end
