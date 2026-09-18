require 'rails_helper'

RSpec.describe EmailCampaign, '#resume!' do
  let(:campaign) { create(:email_campaign, status: :paused, hygiene_pause_reason: 'hygiene_validation_required') }
  let(:account) { campaign.account }
  let!(:recipient) { create(:email_campaign_recipient, email_campaign: campaign) }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_MODE' => 'shadow',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)
  end

  it 'raises a public protection failure instead of claiming resume success with unchecked recipients' do
    expect { campaign.resume! }.to raise_error(CustomExceptions::EmailReputationBlocked) do |error|
      expect(error.protection).to include(resume_allowed: false, protection: include(code: 'hygiene_validation_required'))
    end
    expect(campaign.reload).to be_paused
    expect(campaign.hygiene_pause_reason).to eq('hygiene_validation_required')
    expect(EmailCampaigns::DeliveryJob).not_to have_received(:perform_later)
  end

  it 'refuses resume while recipient import is active, even when existing rows are valid' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    campaign.email_campaign_imports.create!(status: :processing)
    expect { campaign.resume! }.to raise_error(CustomExceptions::EmailReputationBlocked) do |error|
      expect(error.protection).to include(protection: include(code: 'recipient_import_active'))
    end
    expect(campaign.reload).to be_paused
    expect(EmailCampaigns::DeliveryJob).not_to have_received(:perform_later)
  end

  it 'rolls back account release when hygiene changes during the unlocked reputation collection' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    50.times do |i|
      create(:email_campaign_recipient, email_campaign: campaign, email: "accepted#{i}@example.org", status: :sent, sent_at: 1.hour.ago)
    end
    account.update!(internal_attributes: { preserved: 'synthetic', email_campaigns_paused: { reason: 'legacy synthetic' } })
    EmailCampaigns::Reputation::Evaluator.new(account).evaluate!
    state = EmailReputationState.find_by!(account: account)
    snapshot = state.trigger_snapshot
    allow(EmailCampaigns::Reputation::Observation).to receive(:new).and_wrap_original do |original, *args|
      collector = original.call(*args)
      allow(collector).to receive(:collect).and_wrap_original do |collect|
        result = collect.call
        EmailCampaignRecipient.find(recipient.id).update!(preflight_valid_until: 1.second.ago)
        result
      end
      collector
    end
    expect { campaign.resume! }.to raise_error(CustomExceptions::EmailReputationBlocked)
    expect(campaign.reload).to be_paused
    expect(state.reload).to be_blocked
    expect(state.trigger_snapshot).to eq(snapshot)
    expect(account.reload.internal_attributes).to include('preserved' => 'synthetic', 'email_campaigns_paused' => be_present)
    expect(EmailReputationAudit.where(account_id: account.id, action: 'released')).to be_empty
    expect(EmailCampaigns::DeliveryJob).not_to have_received(:perform_later)
  end

  it 'clears both pause fields only after successful validation and publication' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    campaign.update!(pause_reason: { kind: 'manual', code: 'manual_pause' })
    expect(campaign.resume!).to be(true)
    expect(campaign.reload).to be_sending
    expect(campaign.hygiene_pause_reason).to be_nil
    expect(campaign.pause_reason).to eq({})
    expect(EmailCampaigns::DeliveryJob).to have_received(:perform_later).with(campaign.id).once
  end

  it 'keeps a sticky provider block despite valid hygiene and disabled monitoring' do
    recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
    EmailProviderState.create!(provider_key: EmailCampaigns::Reputation::ProviderConfig.new.provider_key, status: 'healthy', blocked: true)
    expect { campaign.resume! }.to raise_error(CustomExceptions::EmailReputationBlocked)
    expect(campaign.reload).to be_paused
    expect(EmailCampaigns::DeliveryJob).not_to have_received(:perform_later)
  end

  {
    pause!: [:sending, :paused], cancel!: [:sending, :canceled],
    claim_for_sending!: [:draft, :sending], mark_sending!: [:scheduled, :sending],
    schedule!: [:draft, :scheduled], finalize!: [:sending, :sent]
  }.each do |action, (initial, expected)|
    it "orders account, state and campaign locks for #{action}, preserving the requested transition" do
      campaign.update!(status: initial)
      recipient.update!(preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
      recipient.update!(status: :delivered, sent_at: Time.current) if action == :finalize!
      EmailReputationState.create!(account: account)
      locks = []
      subscriber = ->(*args) { locks << args.last[:sql] if args.last[:sql].include?('FOR UPDATE') }
      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        if action == :schedule!
          campaign.schedule!(scheduled_at: 1.hour.from_now)
        else
          campaign.public_send(action)
        end
      end
      expect(locks.first(3)).to match([
                                        include('FROM "accounts"'), include('FROM "email_reputation_states"'), include('FROM "email_campaigns"')
                                      ])
      expect(campaign.reload.status).to eq(expected.to_s)
    end
  end

  it 'does not erase unsaved content or its dirty tracking while acquiring delivery locks' do
    campaign.body_mjml = '<mjml><mj-body><mj-text>Synthetic draft</mj-text></mj-body></mjml>'
    original_changes = campaign.changes
    expect { campaign.pause! }.to raise_error(RuntimeError, /unpersisted changes/)
    expect(campaign.changes).to eq(original_changes)
    expect(described_class.find(campaign.id)).to be_paused
  end

  it 'preserves cancellation and recipient history when counter persistence fails' do
    accepted = create(:email_campaign_recipient, email_campaign: campaign, status: :delivered,
                                                 sent_at: 1.hour.ago, ses_message_id: 'synthetic-old-receipt')
    allow(campaign).to receive(:update_columns).and_call_original
    allow(campaign).to receive(:update_columns).with(hash_including(:recipients_count)).and_raise(StandardError, 'synthetic counter failure')
    expect { campaign.cancel! }.to raise_error(StandardError, 'synthetic counter failure')
    expect(campaign.reload).to be_canceled
    expect(recipient.reload).to be_suppressed
    expect(accepted.reload).to have_attributes(status: 'delivered', ses_message_id: 'synthetic-old-receipt', sent_at: be_present)
    expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(false)
  end

  it 'retries bounded cancellation cleanup after an interruption while refusing new claims' do
    stub_const('EmailCampaign::CANCELLATION_BATCH_SIZE', 1)
    another = create(:email_campaign_recipient, email_campaign: campaign)
    allow(campaign).to receive(:with_delivery_lock).and_wrap_original do |lock, &block|
      raise 'synthetic cleanup interruption' if campaign.canceled?

      lock.call(&block)
    end
    expect { campaign.cancel! }.to raise_error('synthetic cleanup interruption')
    expect(campaign.reload).to be_canceled
    expect(EmailCampaigns::Reputation::Admission.new(campaign).claim!(recipient)).to be(false)
    allow(campaign).to receive(:with_delivery_lock).and_call_original
    campaign.cancel!
    expect([recipient.reload.status, another.reload.status]).to eq(%w[suppressed suppressed])
    expect(campaign.reload.suppressed_count).to eq(2)
  end

  it 'checks the import fence inside cancellation without requiring a caller-held child lock' do
    campaign.email_campaign_imports.create!(status: :processing)
    expect(campaign.cancel!).to be(false)
    expect(campaign.reload).to be_paused
    expect(recipient.reload).to be_pending
  end

  it 'collects counters before taking the account lock and persists them in shared lock order' do
    EmailReputationState.create!(account: account)
    queries = []
    subscriber = ->(*args) { queries << args.last[:sql] }
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') { campaign.refresh_counters! }
    account_lock = queries.index { |sql| sql.include?('FROM "accounts"') && sql.include?('FOR UPDATE') }
    aggregates = queries.each_index.select { |index| queries[index].match?(/COUNT\(/i) }
    expect(aggregates).not_to be_empty
    expect(aggregates).to all(be < account_lock)
    expect(campaign.reload.recipients_count).to eq(1)
  end
end
