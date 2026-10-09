require 'rails_helper'

RSpec.describe EmailCampaigns::ReputationEvaluationJob do # rubocop:disable RSpec/SpecFilePathFormat -- durable feedback integration
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }
  let(:campaign) { EmailCampaign.create!(account: account, sender_identity: identity, name: 'Feedback') }
  let!(:recipient) { campaign.email_campaign_recipients.create!(email: 'first@example.com', sent_at: 8.days.ago) }

  before { allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true) }

  it 'queues evaluation from committed harmful feedback, independent of recipient status changes' do
    expect do
      recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
    end.to have_enqueued_job(described_class).with(account.id, kind_of(String))
  end

  it 'does not enqueue rolled-back feedback or direct-inbox delivery events' do
    expect do
      EmailEvent.transaction do
        recipient.email_events.create!(event_type: :complaint)
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(described_class)
    expect(EmailReputationState.find_by(account_id: account.id)).to be_nil
    expect { recipient.email_events.create!(event_type: :delivered) }.not_to have_enqueued_job(described_class)
  end

  it 'reconciles old paused accounts with no recent sends and retains the pause' do
    account.update!(internal_attributes: { email_campaigns_paused: { reason: 'old' } })
    recipient
    EmailCampaigns::GuardrailSweepJob.perform_now
    state = EmailReputationState.find_by!(account_id: account.id)
    expect(state.blocked).to be(true)
    expect(state.current_metrics['sent']).to eq(0)
    expect(state.evaluated_at).to be_present
    expect(state.current_metrics['resume_allowed']).to be(false)
  end

  it 'reconciles persisted feedback even if its enqueue was lost' do
    allow(described_class).to receive(:perform_later)
    recipient.update!(sent_at: Time.current)
    recipient.email_events.create!(event_type: :complaint)
    with_modified_env('EMAIL_REPUTATION_MODE' => 'enforce') { EmailCampaigns::GuardrailSweepJob.perform_now }
    expect(EmailReputationState.find_by!(account_id: account.id).blocked).to be(true)
  end

  it 'coalesces a burst and schedules one follow-up when feedback arrives during collection' do
    20.times { recipient.email_events.create!(event_type: :complaint) }
    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(1)
    state = EmailReputationState.find_by!(account_id: account.id)
    expect(state.feedback_version).to eq(20)
    observation = EmailCampaigns::Reputation::Observation.new(account.id).collect
    recipient.email_events.create!(event_type: :complaint)
    expect(observation.current?(state.reload)).to be(false)
    EmailCampaigns::Reputation::EvaluationQueue.finish(account.id, state.evaluation_lease_token)
    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(2)
  end

  it 'recovers a lost lease on a later feedback and ignores a superseded worker completion' do
    recipient.email_events.create!(event_type: :complaint)
    state = EmailReputationState.find_by!(account_id: account.id)
    old_token = state.evaluation_lease_token
    travel 301.seconds do
      recipient.email_events.create!(event_type: :complaint)
      new_token = state.reload.evaluation_lease_token
      expect(new_token).not_to eq(old_token)
      EmailCampaigns::Reputation::EvaluationQueue.finish(account.id, old_token)
      expect(state.reload.evaluation_lease_token).to eq(new_token)
    end
  end

  %w[Suppressed OnAccountSuppressionList].each do |subtype|
    it "invalidates correction to #{subtype} within the event transaction" do
      recipient.update!(sent_at: Time.current)
      event = recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
      observation = EmailCampaigns::Reputation::Observation.new(account.id).collect
      event.update!(payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
      state = EmailReputationState.find_by!(account_id: account.id)
      expect(observation.current?(state)).to be(false)
      expect(state.feedback_version).to eq(2)
      expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(1)
      collector = EmailCampaigns::Reputation::Metrics.new(account.id)
      expect(collector.harmful_feedback_fingerprint).not_to eq(observation.fingerprint)
      expected = subtype == 'Suppressed' ? { permanent: 1, bounced: 1, provider_prevented: 0 } : { permanent: 0, bounced: 0, provider_prevented: 1 }
      expect(collector.call).to include(expected)
    end
  end

  it 'does not run aggregation for a job whose lease was replaced' do
    recipient.email_events.create!(event_type: :complaint)
    expect(EmailCampaigns::Reputation::Metrics).not_to receive(:new)
    described_class.perform_now(account.id, 'superseded-lease')
  end

  it 'clears the completed lease when its entire feedback generation was published' do
    recipient.email_events.create!(event_type: :complaint)
    state = EmailReputationState.find_by!(account_id: account.id)
    described_class.perform_now(account.id, state.evaluation_lease_token)
    expect(state.reload.evaluation_lease_token).to be_nil
    expect(state.evaluated_feedback_version).to eq(state.feedback_version)
    expect(enqueued_jobs.count { |job| job[:job] == described_class }).to eq(1)
  end
end
