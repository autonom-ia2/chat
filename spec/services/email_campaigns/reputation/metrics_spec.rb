require 'rails_helper'

RSpec.describe EmailCampaigns::Reputation::Metrics do
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }
  let(:campaign) { EmailCampaign.create!(account: account, sender_identity: identity, name: 'Cohort') }
  let(:now) { Time.current.change(usec: 0) }
  let(:service) { described_class.new(account.id, now: now) }

  it 'uses distinct accepted SES sends, correlates late/duplicate feedback and exposes classification' do
    recipients = Array.new(86) do |index|
      campaign.email_campaign_recipients.create!(email: "person#{index}@example.com", sent_at: now - 1.day, status: :sent)
    end
    recipients.first(4).each do |recipient|
      2.times { recipient.email_events.create!(event_type: :bounce, occurred_at: now, payload: { bounce: { bounceType: 'Permanent' } }) }
    end
    recipients[4].email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Transient' } })
    recipients[5].email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Undetermined' } })
    recipients[6].email_events.create!(event_type: :bounce,
                                       payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'OnAccountSuppressionList' } })
    old = campaign.email_campaign_recipients.create!(email: 'old@example.com', sent_at: now - 8.days, status: :sent)
    old.email_events.create!(event_type: :complaint, occurred_at: now)
    unaccepted = campaign.email_campaign_recipients.create!(email: 'ambiguous@example.com', status: :sent)
    unaccepted.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })

    metrics = service.call
    expect(metrics).to include(sent: 86, permanent: 4, transient: 1, unknown: 1, provider_prevented: 1, complaints: 0)
    expect(EmailCampaigns::Reputation::Policy.new({}).evaluate(metrics)).to include(level: 'high_risk', pause: false)
  end

  it 'includes the exact cohort boundary and excludes future sends and other tenants/direct inbox' do
    campaign.email_campaign_recipients.create!(email: 'boundary@example.com', sent_at: now - 7.days)
    campaign.email_campaign_recipients.create!(email: 'outside@example.com', sent_at: now - 7.days - 1.second)
    campaign.email_campaign_recipients.create!(email: 'future@example.com', sent_at: now + 1.second)
    direct = campaign.dup
    direct.name = 'Direct'
    direct.save!
    direct.update!(delivery_mode: :direct_inbox, sender_inbox: create(:channel_email, account: account).inbox)
    direct.email_campaign_recipients.create!(email: 'direct@example.com', sent_at: now)
    other = create(:account)
    other_identity = EmailSenderIdentity.create!(account: other, domain: 'other.example.com', status: :verified)
    other_campaign = EmailCampaign.create!(account: other, sender_identity: other_identity, name: 'Other')
    other_campaign.email_campaign_recipients.create!(email: 'other@example.com', sent_at: now)

    expect(service.call[:sent]).to eq(1)
  end

  it 'keeps a duplicate from advancing the harmful feedback fingerprint but detects new late feedback' do
    first = campaign.email_campaign_recipients.create!(email: 'first@example.com', sent_at: now - 8.days)
    second = campaign.email_campaign_recipients.create!(email: 'second@example.com', sent_at: now - 8.days)
    first.email_events.create!(event_type: :complaint)
    original = service.harmful_feedback_fingerprint
    first.email_events.create!(event_type: :complaint)
    expect(service.harmful_feedback_fingerprint).to eq(original)
    second.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent' } })
    expect(service.harmful_feedback_fingerprint).not_to eq(original)
  end

  it 'counts global Suppressed as permanent harmful feedback, deduplicates it and pauses at five percent' do
    recipients = Array.new(100) do |index|
      campaign.email_campaign_recipients.create!(email: "suppressed#{index}@example.com", sent_at: now - 1.hour)
    end
    fingerprint = service.harmful_feedback_fingerprint
    recipients.first(5).each do |recipient|
      recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'Suppressed' } })
    end
    expect(service.call).to include(sent: 100, permanent: 5, bounced: 5, provider_prevented: 0)
    harmful = service.harmful_feedback_fingerprint
    expect(harmful).not_to eq(fingerprint)
    recipients.first.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'Suppressed' } })
    expect(service.harmful_feedback_fingerprint).to eq(harmful)
    expect(service.call).to include(permanent: 5, bounced: 5)
    policy = EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce')
    expect(EmailCampaigns::Reputation::Evaluator.new(account, policy: policy).evaluate!).to include(blocked: true)
  end

  it 'includes late global Suppressed feedback in the harmful fingerprint outside the local cohort' do
    recipient = campaign.email_campaign_recipients.create!(email: 'late-suppressed@example.com', sent_at: now - 8.days)
    original = service.harmful_feedback_fingerprint
    recipient.email_events.create!(event_type: :bounce, occurred_at: now,
                                   payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'Suppressed' } })
    expect(service.call).to include(sent: 0, permanent: 0, bounced: 0, provider_prevented: 0)
    expect(service.harmful_feedback_fingerprint).not_to eq(original)
  end

  %w[OnAccountSuppressionList OnTenantSuppressionList EmailValidationSuppressed UnsubscribedRecipient].each do |subtype|
    it "counts #{subtype} only as prevention, without changing the harmful fingerprint or pausing" do
      recipients = Array.new(100) do |index|
        campaign.email_campaign_recipients.create!(email: "prevented#{index}@example.com", sent_at: now - 1.hour)
      end
      fingerprint = service.harmful_feedback_fingerprint
      recipients.first(5).each do |recipient|
        2.times do
          recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
        end
      end
      expect(service.call).to include(sent: 100, permanent: 0, transient: 0, unknown: 0, bounced: 0, provider_prevented: 5)
      expect(service.harmful_feedback_fingerprint).to eq(fingerprint)
      recipients[5].email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
      expect(service.harmful_feedback_fingerprint).to eq(fingerprint)
      policy = EmailCampaigns::Reputation::Policy.new('EMAIL_REPUTATION_MODE' => 'enforce')
      expect(EmailCampaigns::Reputation::Evaluator.new(account, policy: policy).evaluate!).to include(blocked: false)
    end
  end

  it 'changes the fixed-size fingerprint when an existing harmful outcome is corrected' do
    recipient = campaign.email_campaign_recipients.create!(email: 'correction@example.com', sent_at: now)
    empty = service.harmful_feedback_fingerprint
    event = recipient.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'General' } })
    original = service.harmful_feedback_fingerprint
    event.update!(payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'NoEmail' } })
    no_email = service.harmful_feedback_fingerprint
    expect(no_email).not_to eq(original)
    event.update!(payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'Suppressed' } })
    expect(service.call).to include(permanent: 1, bounced: 1, provider_prevented: 0)
    suppressed = service.harmful_feedback_fingerprint
    expect(suppressed).not_to eq(no_email)
    expect(suppressed).not_to eq(empty)
    event.update!(payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'OnAccountSuppressionList' } })
    expect(service.call).to include(permanent: 0, bounced: 0, provider_prevented: 1)
    expect(service.harmful_feedback_fingerprint).to eq(empty)
  end
end
