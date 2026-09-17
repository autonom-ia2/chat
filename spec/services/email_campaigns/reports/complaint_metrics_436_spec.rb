require 'rails_helper'

RSpec.describe EmailCampaigns::Reports::Metrics do # rubocop:disable RSpec/SpecFilePathFormat
  let(:campaign) { create(:email_campaign) }
  let(:metrics) { described_class.new([campaign]) }

  EmailCampaigns::ComplaintClassifier::PREVENTED_SUBTYPES.each do |subtype|
    it "excludes duplicate #{subtype} complaints from spam counters and rates while retaining activity" do
      row = create(:email_campaign_recipient, email_campaign: campaign, status: :suppressed, sent_at: 1.hour.ago)
      2.times { row.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: subtype } }) }

      expect(metrics.by_campaign.fetch(campaign.id)).to include(complained: 0, provider_prevented: 1, complaint_rate: 0.0)
      expect(metrics.summary).to include(complained: 0, provider_prevented: 1, complaint_rate: 0.0)
      expect(metrics.summary[:activity]).to include('complaint' => 2)
      expect(metrics.summary[:reputation_coverage]).to include(complaints: 0, provider_prevented: 1)
      expect(metrics.summary[:rate_metadata][:complaint_rate]).to include(numerator: 0, denominator: 1)
    end
  end

  [nil, {}, { complaintSubType: nil }, { complaintSubType: 'UnknownSubtype' }].each do |complaint|
    it "keeps #{complaint.inspect} as real feedback even with historical and later provider prevention" do
      row = create(:email_campaign_recipient, email_campaign: campaign, status: :complained, sent_at: 40.days.ago)
      EmailCampaigns::ComplaintClassifier::PREVENTED_SUBTYPES.each_with_index do |subtype, index|
        row.email_events.create!(event_type: :complaint, occurred_at: (index + 1).hours.ago,
                                 payload: { complaint: { complaintSubType: subtype } })
        2.times do
          row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: subtype } })
        end
      end
      2.times { row.email_events.create!(event_type: :complaint, occurred_at: 90.minutes.ago, payload: { complaint: complaint }) }

      expect(metrics.summary).to include(complained: 1, provider_prevented: 1, complaint_rate: 100.0, permanent_bounces: 0)
      expect(metrics.summary[:activity]).to include('complaint' => 4, 'bounce' => 4)
      expect(metrics.summary[:reputation_coverage]).to include(complaints: 1, provider_prevented: 1)
      expect(metrics.summary[:rate_metadata][:complaint_rate]).to include(numerator: 1, denominator: 1)
    end
  end

  it 'counts prevention once across bounce and complaint, scoped to each campaign and accepted SES coverage' do
    inbox = create(:inbox, :with_email, account: campaign.account)
    direct = create(:email_campaign, account: campaign.account, delivery_mode: :direct_inbox, sender_identity: nil, sender_inbox: inbox)
    foreign = create(:email_campaign)
    rows = [create(:email_campaign_recipient, email_campaign: campaign, sent_at: 1.hour.ago),
            create(:email_campaign_recipient, email_campaign: campaign),
            create(:email_campaign_recipient, email_campaign: direct, sent_at: 1.hour.ago),
            create(:email_campaign_recipient, email_campaign: foreign, sent_at: 1.hour.ago)]
    rows.each do |row|
      2.times do
        row.email_events.create!(event_type: :bounce, payload: { bounce: { bounceType: 'Permanent', bounceSubType: 'OnAccountSuppressionList' } })
        row.email_events.create!(event_type: :complaint, payload: { complaint: { complaintSubType: 'OnTenantSuppressionList' } })
      end
    end
    result = described_class.new([campaign, direct])
    expect(result.summary).to include(recipients: 3, provider_prevented: 3, complained: 0, complaint_rate: 0.0)
    expect(result.summary[:reputation_coverage]).to include(sent: 1, complaints: 0, provider_prevented: 1, excluded_direct_sent: 1)
    expect(result.summary[:activity]).to include('bounce' => 6, 'complaint' => 6)
    expect(result.by_campaign.fetch(campaign.id)).to include(provider_prevented: 2, complained: 0)
    expect(result.by_campaign.fetch(direct.id)).to include(provider_prevented: 1, complained: 0, complaint_rate: nil)
  end
end
