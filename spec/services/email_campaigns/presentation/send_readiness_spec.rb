require 'rails_helper'

RSpec.describe EmailCampaigns::Presentation::SendReadiness, :aggregate_failures do
  let(:campaign) { create(:email_campaign, status: :draft) }

  around do |example|
    with_modified_env EMAIL_CAMPAIGN_HYGIENE_MODE: 'shadow',
                      EMAIL_REPUTATION_PROVIDER_MONITOR: 'false',
                      EMAIL_REPUTATION_PROVIDER_BLOCK: 'false' do
      example.run
    end
  end

  it 'keeps a healthy provider sendable despite local reputation history and excludes protected addresses' do
    EmailReputationState.create!(account: campaign.account, blocked: true, level: 'high_risk',
                                 current_metrics: { 'permanent' => 12, 'sent' => 100 })

    eligible = create(:email_campaign_recipient, email_campaign: campaign, email: 'eligible@example.org')
    hard_bounce = create(:email_campaign_recipient, email_campaign: campaign, email: 'hard-bounce@example.org')
    complaint = create(:email_campaign_recipient, email_campaign: campaign, email: 'complaint@example.org')
    unsubscribe = create(:email_campaign_recipient, email_campaign: campaign, email: 'unsubscribe@example.org')

    EmailSuppression.create!(account: campaign.account, email: hard_bounce.email, reason: 'hard_bounce', source: 'ses')
    EmailSuppression.create!(account: campaign.account, email: complaint.email, reason: 'complaint', source: 'ses')
    EmailSuppression.create!(account: campaign.account, email: unsubscribe.email, reason: 'unsubscribe', source: 'link')

    result = described_class.new(campaign).call

    expect(result).to include(can_send: true, eligible_recipients: 1, protected_recipients: 3)
    expect(result.fetch(:checks)).to include(
      subject: true,
      content: true,
      sender: true,
      recipients: true,
      import: true,
      hygiene: true,
      provider: true
    )
    expect(campaign.email_campaign_recipients.where(id: eligible.id)).to exist
  end

  it 'keeps an incomplete draft out of the send while reporting the missing content' do
    campaign.update!(subject: nil, body_html: nil)
    create(:email_campaign_recipient, email_campaign: campaign)

    result = described_class.new(campaign).call

    expect(result.fetch(:can_send)).to be(false)
    expect(result.fetch(:checks)).to include(subject: false, content: false, recipients: true)
  end

  it 'keeps the send unavailable while a recipient import is active' do
    create(:email_campaign_recipient, email_campaign: campaign)
    campaign.email_campaign_imports.create!

    result = described_class.new(campaign).call

    expect(result.fetch(:can_send)).to be(false)
    expect(result.fetch(:checks)).to include(import: false)
  end

  it 'honors an unhealthy provider gate without turning it into a local account reputation decision' do
    create(:email_campaign_recipient, email_campaign: campaign)
    allow(EmailCampaigns::Guardrail).to receive(:protection).and_return(kind: 'provider', code: 'provider_blocked')

    result = described_class.new(campaign).call

    expect(result.fetch(:can_send)).to be(false)
    expect(result.fetch(:checks)).to include(provider: false)
  end
end
