require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Metrics do # rubocop:disable RSpec/SpecFilePathFormat -- complaint classification regressions
  let(:account) { create(:account) }
  let(:campaign) { create(:email_campaign, account: account) }
  let(:recipient) { create(:email_campaign_recipient, email_campaign: campaign, status: :sent, sent_at: 1.hour.ago) }
  let(:collector) { described_class.new(account.id) }
  let(:policy) { EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce') }
  let(:evaluator) { EmailCampaigns::Reputation::Evaluator.new(account, policy: policy) }

  before { allow(EmailCampaigns::ReputationEvaluationJob).to receive(:perform_later) }

  after { expect(WebMock).not_to have_requested(:any, /./) } # rubocop:disable RSpec/ExpectInHook -- zero HTTP contract for every example

  %w[OnAccountSuppressionList OnTenantSuppressionList].each do |subtype|
    it "excludes Complaint/#{subtype} and replays from complaints/fingerprint without a false 0.1 percent pause" do
      EmailCampaignRecipient.insert_all!(Array.new(999) do |index| # rubocop:disable Rails/SkipsModelValidations
        { email_campaign_id: campaign.id, email: "accepted-#{index}@example.com", status: 1, sent_at: 1.hour.ago,
          created_at: Time.current, updated_at: Time.current }
      end)
      recipient
      original = collector.harmful_feedback_fingerprint
      2.times { recipient.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: subtype } }) }
      metrics = collector.call
      expect(metrics).to include(sent: 1000, complaints: 0, provider_prevented: 1)
      expect(collector.harmful_feedback_fingerprint).to eq(original)
      expect(policy.evaluate(metrics)).to include(complaint_ratio: 0.0, pause: false, spam_alert: false, level: 'healthy')
      expect(evaluator.evaluate!).to include(blocked: false)
      expect(EmailReputationAudit.where(account: account, action: %w[paused risk_alert override_revoked])).to be_empty
      recipient.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: nil } })
      expect(collector.call).to include(complaints: 1, provider_prevented: 1)
      expect(policy.evaluate(collector.call)).to include(complaint_ratio: 0.001, pause: true, spam_alert: true)
    end

    it "keeps the override fingerprint and incident intact after late Complaint/#{subtype}" do
      recipient.update!(sent_at: 8.days.ago)
      account.update!(internal_attributes: { email_campaigns_paused: { reason: 'synthetic legacy protection' } })
      evaluator.evaluate!
      state = EmailReputationState.find_by!(account: account)
      snapshot = state.trigger_snapshot
      state.update!(override: { expires_at: 1.hour.from_now.iso8601, remaining: 2, feedback_fingerprint: collector.harmful_feedback_fingerprint })
      2.times { recipient.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: subtype } }) }
      expect(evaluator.evaluate!).to include(blocked: true, override_active: true)
      expect(state.reload.trigger_snapshot).to eq(snapshot)
      expect(state.override).not_to have_key('revoked_at')
      expect(EmailReputationAudit.where(account: account, action: %w[override_revoked risk_alert])).to be_empty
      recipient.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: 'FutureUnknown' } })
      expect(evaluator.evaluate!).to include(override_active: false)
      expect(state.reload.override['revocation_reason']).to eq('new_harmful_feedback')
    end
  end

  [{}, { complaint: {} }, { complaint: nil }, { complaint: { complaintSubType: nil } },
   { complaint: { complaintSubType: 'FutureUnknown' } }].each do |payload|
    it "counts #{payload.inspect} as a real complaint, with a stable replay fingerprint" do
      recipient
      original = collector.harmful_feedback_fingerprint
      recipient.email_events.create!(event_type: :complaint, payload: payload)
      harmful = collector.harmful_feedback_fingerprint
      recipient.email_events.create!(event_type: :complaint, payload: payload)
      expect(collector.call).to include(complaints: 1, provider_prevented: 0)
      expect(harmful).not_to eq(original)
      expect(collector.harmful_feedback_fingerprint).to eq(harmful)
      expect(policy.evaluate(collector.call)).to include(pause: true, spam_alert: true)
    end
  end

  %w[shadow warning enforce].each do |mode|
    it "does not pause or alert on provider complaints in #{mode}" do
      recipients = create_list(:email_campaign_recipient, 50, email_campaign: campaign, sent_at: 1.hour.ago)
      recipients.first.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: 'OnAccountSuppressionList' } })
      selected_policy = EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => mode)
      expect(EmailCampaigns::Reputation::Evaluator.new(account, policy: selected_policy).evaluate!).to include(blocked: false, level: 'healthy')
      expect(EmailReputationAudit.where(account: account)).to be_empty
    end
  end
end
