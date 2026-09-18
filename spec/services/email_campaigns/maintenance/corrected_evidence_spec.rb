require 'rails_helper'

# Same-key promotion is supplied by PR438. Keep these examples active across the rebase.
# rubocop:disable RSpec/MultipleExpectations -- Each correction flow checks persistence, retained audit and replay together.
RSpec.describe 'Corrected historical protection', type: :model do
  let(:account) { create(:account) }
  let(:actor) { create(:user, account: account, type: 'SuperAdmin').becomes(SuperAdmin) }
  let(:campaign) { create(:email_campaign, account: account, status: :paused) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, ses_message_id: 'm1') }
  let(:config) { EmailCampaigns::Maintenance::Config.new('EMAIL_CAMPAIGN_PROTECTION_BACKFILL_ENABLED' => 'true') }
  let(:parameters) { { mode: 'apply', confirm: 'apply', reason: 'Reviewed synthetic correction', idempotency_key: 'corrected_442_apply' } }
  let(:run) { EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config) }
  let(:worker) { EmailCampaigns::Maintenance::HistoricalProtectionBackfill }
  let(:registry) { EmailCampaigns::SuppressionRegistry.new(account: account, email: recipient.email, campaign: campaign) }
  let(:suppression_events) { EmailSuppressionEvent.where(account_id: account.id) }
  let(:historical) do
    recipient.email_events.create!(event_type: :bounce, occurred_at: 3.years.ago, payload: {
                                     'mail' => { 'messageId' => 'm1' },
                                     'bounce' => { 'bounceType' => 'Undetermined', 'bounceSubType' => 'Undetermined' }
                                   })
  end
  let(:live_event) do
    registry.record!(reason: 'unknown_bounce', source: 'ses', event_key: 'ses:m1:bounce', occurred_at: historical.occurred_at,
                     metadata: { 'classification' => 'unknown', 'reason_code' => 'undetermined_bounce' }).event
  end

  {
    'General' => 'hard_bounce',
    'Suppressed' => 'provider_suppression',
    'OnAccountSuppressionList' => 'provider_suppression',
    'OnTenantSuppressionList' => 'provider_suppression'
  }.each do |subtype, reason|
    context "when the persisted bounce is corrected to Permanent/#{subtype}" do
      before do
        live_event
        historical.update!(payload: historical.payload.merge('bounce' => { 'bounceType' => 'Permanent', 'bounceSubType' => subtype }))
      end

      it 'previews without mutation, completes apply with the live key and suppresses a subsequent reimport' do
        original = live_event.attributes
        state = EmailSuppressionState.find_by!(account: account, email: recipient.email)
        before = [state.attributes, historical.attributes, recipient.reload.attributes, campaign.reload.attributes]
        expect(state.active).to be(false)
        expect(EmailSuppression.where(account: account)).to be_empty
        evidence = EmailCampaigns::Maintenance::Evidence.new(historical.reload, account_id: account.id)
        expect(evidence).to have_attributes(event_key: 'ses:m1:bounce', reason: reason)
        preview_parameters = parameters.except(:mode, :confirm).merge(idempotency_key: 'corrected_442_preview')
        preview = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config, parameters: preview_parameters)
        2.times { worker.new(run: preview.reload, config: config).call }
        expect(preview.reload).to have_attributes(status: 'completed', event_cursor: historical.id, error_code: nil)
        expect(preview.counts).to include('events_processed' => 1, 'eligible_events' => 1, 'unprotected_candidate_events' => 1)
        expect([state.reload.attributes, historical.reload.attributes, recipient.reload.attributes, campaign.reload.attributes]).to eq(before)
        expect(suppression_events.sole.attributes).to eq(original)
        expect(EmailSuppression.where(account: account)).to be_empty

        2.times { worker.new(run: run.reload, config: config).call }
        expect(run.reload).to have_attributes(status: 'completed', event_cursor: historical.id, error_code: nil)
        expect(run.counts.slice('events_processed', 'eligible_events', 'unprotected_candidate_events')).to eq(preview.counts)
        expect(state.reload).to have_attributes(active: true, reason: reason, expires_at: nil)
        expect(EmailSuppression.find_by!(account: account, email: recipient.email).reason).to eq(reason)
        expect(live_event.reload.attributes).to eq(original)
        correction = suppression_events.where(reason: reason).sole
        expect(correction).to have_attributes(source: 'backfill', occurred_at: historical.occurred_at)
        expect(correction.metadata).to include('historical_event_id' => historical.id, 'maintenance_run_id' => run.id)
        expect(suppression_events.count).to eq(2)

        identity = create(:email_sender_identity, account: account, domain: 'another.example', from_email: 'sender@another.example')
        future = create(:email_campaign, account: account, sender_identity: identity, from_email: identity.from_email)
        with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow', EMAIL_CAMPAIGN_HYGIENE_DNS_ENABLED: 'false' do
          result = EmailCampaigns::RecipientImporter.new(future, "name,email\nSynthetic,#{recipient.email.upcase}\n",
                                                         filename: 'synthetic.csv').perform
          expect(result.suppressed).to eq(1)
          expect(future.email_campaign_recipients.sole).to be_suppressed
        end
        expect([historical.reload.attributes, recipient.reload.attributes, campaign.reload.attributes]).to eq(before.drop(1))
      end

      it 'does not duplicate the correction on job replay, identical requests or a new backfill' do
        2.times { worker.new(run: run.reload, config: config).call }
        expect(run.reload.status).to eq('completed')
        state = EmailSuppressionState.find_by!(account: account, email: recipient.email)
        expect(state).to have_attributes(active: true, reason: reason, expires_at: nil)
        legacy = EmailSuppression.find_by!(account: account, email: recipient.email)
        audit = suppression_events.order(:id).map(&:attributes)
        before = [run.attributes, state.attributes, legacy.attributes]

        repeated = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, parameters: parameters, config: config)
        expect(repeated.id).to eq(run.id)
        2.times { worker.new(run: repeated.reload, config: config).call }
        expect([run.reload.attributes, state.reload.attributes, legacy.reload.attributes]).to eq(before)
        expect(suppression_events.order(:id).map(&:attributes)).to eq(audit)

        fresh = EmailCampaigns::Maintenance::Start.call(account: account, actor: actor, config: config,
                                                        parameters: parameters.merge(idempotency_key: 'corrected_442_fresh'))
        worker.new(run: fresh, config: config).call
        expect(fresh.reload).to have_attributes(status: 'pending', phase: 'legacy', event_cursor: historical.id)
        expect(fresh.counts).to include('events_processed' => 1, 'eligible_events' => 1, 'duplicate_events' => 1)
        expect(suppression_events.order(:id).map(&:attributes)).to eq(audit)
        expect(state.reload.attributes).to eq(before[1])
        worker.new(run: fresh.reload, config: config).call
        expect(fresh.reload.status).to eq('completed')
        # A fresh horizon also mirrors the newly created legacy row; that is separate evidence, not another promotion.
        expect(suppression_events.where.not(event_key: "historical:email_suppression:#{legacy.id}").order(:id).map(&:attributes)).to eq(audit)
        expect(suppression_events.where(event_key: "historical:email_suppression:#{legacy.id}").count).to eq(1)
        expect(state.reload).to have_attributes(active: true, reason: reason, expires_at: nil)
        expect(legacy.reload.attributes).to eq(before[2])
      end
    end
  end

  %w[unsubscribe complaint manual hard_bounce].each do |strong_reason|
    it "retains #{strong_reason} and append-only history when the same bounce key is corrected to provider prevention" do
      strong = registry.block!(reason: strong_reason, source: 'ses', event_key: "existing:#{strong_reason}").event
      original = [strong.attributes, live_event.attributes]
      legacy = EmailSuppression.find_by!(account: account, email: recipient.email)
      legacy_before = legacy.attributes
      historical.update!(payload: historical.payload.merge('bounce' => {
                                                             'bounceType' => 'Permanent', 'bounceSubType' => 'OnAccountSuppressionList'
                                                           }))
      evidence = EmailCampaigns::Maintenance::Evidence.new(historical.reload, account_id: account.id)
      expect(evidence).to have_attributes(event_key: 'ses:m1:bounce', reason: 'provider_suppression')
      2.times { worker.new(run: run.reload, config: config).call }
      expect(run.reload).to have_attributes(status: 'completed', event_cursor: historical.id, error_code: nil)
      expect(EmailSuppressionState.find_by!(account: account, email: recipient.email))
        .to have_attributes(active: true, reason: strong_reason, expires_at: nil)
      expect(legacy.reload.attributes).to eq(legacy_before)
      expect([strong.reload.attributes, live_event.reload.attributes]).to eq(original)
      correction = suppression_events.where(reason: 'provider_suppression').sole
      expect(correction).to have_attributes(source: 'backfill', occurred_at: historical.occurred_at)
      expect(correction.metadata).to include('historical_event_id' => historical.id, 'maintenance_run_id' => run.id,
                                             'classification' => 'unknown', 'reason_code' => 'provider_suppression')
      audit = suppression_events.order(:id).map(&:attributes)
      worker.new(run: run.reload, config: config).call
      expect(suppression_events.order(:id).map(&:attributes)).to eq(audit)
    end
  end

  it 'does not erase an existing complaint when its persisted same-key payload is corrected to provider prevention' do
    event = recipient.email_events.create!(event_type: :complaint, payload: { 'mail' => { 'messageId' => 'm1' } })
    original = registry.block!(reason: 'complaint', source: 'ses', event_key: 'ses:m1:complaint', occurred_at: event.occurred_at).event
    audit = original.attributes
    legacy = EmailSuppression.find_by!(account: account, email: recipient.email)
    legacy_before = legacy.attributes
    event.update!(payload: event.payload.merge('complaint' => { 'complaintSubType' => 'OnTenantSuppressionList' }))
    evidence = EmailCampaigns::Maintenance::Evidence.new(event.reload, account_id: account.id)
    expect(evidence).to have_attributes(event_key: 'ses:m1:complaint', reason: 'provider_suppression')
    2.times { worker.new(run: run.reload, config: config).call }
    expect(run.reload).to have_attributes(status: 'completed', event_cursor: event.id, error_code: nil)
    expect(EmailSuppressionState.find_by!(account: account, email: recipient.email))
      .to have_attributes(active: true, reason: 'complaint', expires_at: nil)
    expect(legacy.reload.attributes).to eq(legacy_before)
    expect(original.reload.attributes).to eq(audit)
    expect(suppression_events.where(event_key: 'ses:m1:complaint').sole.id).to eq(original.id)
  end
end
# rubocop:enable RSpec/MultipleExpectations
