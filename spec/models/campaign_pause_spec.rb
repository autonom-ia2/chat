require 'rails_helper'

RSpec.describe CampaignPause, :aggregate_failures do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }

  def pause_for(pausable, **attrs)
    described_class.create!({ account: account, pausable: pausable, source: 'manual', reason_code: 'manual_pause',
                              paused_at: Time.current }.merge(attrs))
  end

  it 'covers the Chatwoot campaign and the fork e-mail campaign' do
    email_campaign = create(:email_campaign, account: account)

    expect(pause_for(campaign)).to be_persisted
    expect(pause_for(email_campaign, source: 'email_protection')).to be_persisted
    expect(described_class.open_for(email_campaign).source).to eq('email_protection')
  end

  it 'refuses other pausable types and a campaign of another account' do
    expect(described_class.new(account: account, pausable: account.contacts.create!(name: 'X'), source: 'manual', reason_code: 'x',
                               paused_at: Time.current)).not_to be_valid
    expect(described_class.new(account: create(:account), pausable: campaign, source: 'manual', reason_code: 'x',
                               paused_at: Time.current)).not_to be_valid
  end

  it 'keeps at most one open pause per campaign' do
    pause_for(campaign)

    expect { pause_for(campaign) }.to raise_error(ActiveRecord::RecordNotUnique)
    described_class.open_for(campaign).update!(resumed_at: Time.current)
    expect(pause_for(campaign)).to be_open
  end
end
