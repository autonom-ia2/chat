require 'rails_helper'

RSpec.describe EmailCampaigns::SuppressionRegistry do # rubocop:disable RSpec/SpecFilePathFormat -- mixed-version integration
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:account) { campaign.account }
  let(:email) { 'person+tag@example.org' }
  let(:registry) { described_class.new(account: account, email: ' Person+tag@Example.org ') }

  %w[unsubscribe complaint hard_bounce].each do |reason|
    it "keeps an old #{reason} writer authoritative after new transient observations and rollback/reupgrade" do
      recipient = create(:email_campaign_recipient, email_campaign: campaign, email: email)
      registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'new:1')
      expect(EmailSuppression.where(account: account)).to be_empty
      # These are the old writer operations, including find_or_create without promotion.
      if reason == 'unsubscribe'
        2.times do
          EmailSuppression.find_or_create_by!(account_id: account.id, email: email) do |row|
            row.reason = 'unsubscribe'
            row.source = 'link'
          end
        end
      else
        EmailSuppression.create!(account_id: account.id, email: email, reason: reason, source: 'ses')
      end
      # During rollback the old reader sees a positive legacy row.
      expect(EmailSuppression.where(account_id: account.id).pluck(:email)).to include(email)
      3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "new-again:#{i}") }
      travel 74.hours do
        expect(EmailSuppression.suppressed?(account, email.upcase)).to be true
        expect(EmailSuppression.blocking_reasons_for(account, [email.upcase])).to eq(email => reason)
        expect(EmailSuppression.suppressed_set_for(create(:account))).to be_empty
        csv = "name,email\nPerson,#{email}\n"
        future = create(:email_campaign, account: account, sender_identity: campaign.sender_identity)
        result = EmailCampaigns::RecipientImporter.new(future, csv, filename: 'synthetic.csv').perform
        expect(result.suppressed).to eq(1)
        expect(EmailCampaigns::DeliveryClaim.new(campaign).claim(recipient)).to eq(:suppressed)
      end
    end
  end

  it 'never releases old opt-out when an active new quarantine expires' do
    3.times { |i| registry.record!(reason: 'temporary_failure', source: 'ses', event_key: "soft:#{i}") }
    expect(EmailSuppression.suppressed?(account, email)).to be true
    EmailSuppression.find_or_create_by!(account_id: account.id, email: email) { |row| row.reason = 'unsubscribe' }
    travel 74.hours do
      expect(EmailSuppression.suppressed_set_for(account)).to include(email)
      expect(EmailSuppression.blocking_reasons_for(account, [email])).to eq(email => 'unsubscribe')
    end
    expect do
      registry.release!(source: 'manual', event_key: 'release', authorization: 'arbitrary-reference')
    end.to raise_error(ArgumentError)
  end
end
