require 'rails_helper'

# #1002 (K4): the e-mail button that leads to WhatsApp carries the campaign's #CODE, the same
# marker as a tracked link; the message with it gets the campaign mark.
RSpec.describe CampaignJourney::ReplyCodes do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+15551234567', provider: 'whatsapp_cloud', validate_provider_config: false,
                              sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:email_campaign) { create(:email_campaign, account: account, name: 'Novidades de outubro') }

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  describe '.code_for!' do
    it 'creates one code per campaign, in the tracked link format' do
      code = described_class.code_for!(email_campaign)

      expect(code).to match(Ctwa::TrackedLink::CODE_FORMAT)
      expect(described_class.code_for!(email_campaign)).to eq(code)
      expect(CampaignReplyCode.where(campaign: email_campaign).count).to eq(1)
    end
  end

  describe '.wa_link' do
    it 'builds the wa.me link with the code at the end of the prefilled text' do
      code = described_class.code_for!(email_campaign)

      link = described_class.wa_link(email_campaign, inbox: inbox, text: 'Quero falar')

      expect(link).to eq("https://wa.me/15551234567?text=#{CGI.escape("Quero falar ##{code}")}")
    end
  end

  describe 'K4 — message with the campaign code' do
    it 'marks the conversation with the e-mail campaign through the tracked link attributor' do
      code = described_class.code_for!(email_campaign)
      conversation = create(:conversation, account: account, inbox: inbox)

      Ctwa::TrackedLinkAttributor.attribute!(conversation, "Quero falar ##{code}")

      expect(conversation.reload.additional_attributes['campaign']).to include(
        'source' => 'campaign_email', 'source_type' => 'campaign_email',
        'source_id' => "campaign:email:#{email_campaign.id}", 'headline' => 'Novidades de outubro'
      )
    end

    it 'ignores the code of a campaign of another account' do
      other_campaign = create(:email_campaign, account: create(:account))
      code = described_class.code_for!(other_campaign)
      conversation = create(:conversation, account: account, inbox: inbox)

      Ctwa::TrackedLinkAttributor.attribute!(conversation, "Oi ##{code}")

      expect(conversation.reload.additional_attributes).not_to have_key('campaign')
    end

    it 'does nothing with the journey off' do
      code = described_class.code_for!(email_campaign)
      conversation = create(:conversation, account: account, inbox: inbox)

      with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'false') do
        Ctwa::TrackedLinkAttributor.attribute!(conversation, "Oi ##{code}")
      end

      expect(conversation.reload.additional_attributes).not_to have_key('campaign')
    end
  end
end
