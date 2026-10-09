require 'rails_helper'

RSpec.describe EmailCampaigns::TenantProtectionRetirementJob do
  let(:account) { create(:account) }
  let(:identity) { EmailSenderIdentity.create!(account: account, domain: 'example.com', status: :verified) }

  around do |example|
    with_modified_env(
      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false',
      'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
      'EMAIL_CAMPAIGN_HYGIENE_MODE' => 'shadow'
    ) { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::DeliveryJob).to receive(:perform_later)
  end

  def campaign(name:, pause_reason: {}, last_error: nil)
    record = EmailCampaign.create!(
      account: account, sender_identity: identity, name: name, subject: 'Hello',
      body_html: '<p>Hello</p>', status: :paused,
      pause_reason: pause_reason, last_error: last_error
    )
    record.email_campaign_recipients.create!(email: "#{name.parameterize}@example.org")
    record
  end

  it 'reconciles structured local reputation pauses' do
    structured = campaign(
      name: 'structured',
      pause_reason: { kind: 'reputation', code: 'reputation_paused' }
    )
    manual = campaign(
      name: 'manual',
      pause_reason: { kind: 'manual', code: 'manual_pause' }
    )

    described_class.perform_now(account.id)

    expect(structured.reload).to be_sending
    expect(manual.reload).to be_paused
  end


  it 'reconciles the legacy guardrail marker without touching unrelated pauses' do
    legacy = campaign(
      name: 'legacy',
      last_error: 'Envios pausados pelo guardrail de reputação da conta (bounce_rate=5.81%)'
    )
    unrelated = campaign(name: 'other', last_error: 'Falha operacional qualquer')

    described_class.perform_now(account.id)

    expect(legacy.reload).to be_sending
    expect(legacy.pause_reason).to eq({})
    expect(legacy.last_error).to be_nil
    expect(unrelated.reload).to be_paused
  end
end
