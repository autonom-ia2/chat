require 'rails_helper'

# #993 (PRD §6.8, M5): who talks through a live chat campaign of the website gets its mark.
RSpec.describe CampaignJourney::ReplyMarker do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:inbox) { web_widget.inbox }
  let(:contact) { create(:contact, account: account) }
  let(:live_chat) do
    create(:campaign, account: account, inbox: inbox, title: 'Boas-vindas no site', campaign_type: :ongoing,
                      trigger_rules: { url: 'https://exemplo.com.br', time_on_page: 10 })
  end

  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  def visitor_writes(conversation)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Oi')
  end

  it 'marks a conversation started by the live chat campaign with campaign_live_chat' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, campaign: live_chat)

    expect(described_class.new(visitor_writes(conversation)).perform).to be_truthy

    expect(conversation.reload.additional_attributes['campaign']).to include(
      'source_type' => 'campaign_live_chat', 'source_id' => "campaign:live_chat:#{live_chat.id}",
      'headline' => 'Boas-vindas no site'
    )
  end

  it 'marks only once, and never a website conversation without a campaign' do
    conversation = create(:conversation, account: account, inbox: inbox, contact: contact, campaign: live_chat)
    described_class.new(visitor_writes(conversation)).perform
    described_class.new(visitor_writes(conversation)).perform
    plain = create(:conversation, account: account, inbox: inbox, contact: contact)

    expect(described_class.new(visitor_writes(plain)).perform).to be(false)
    expect(Array(conversation.reload.additional_attributes['campaign_source_ids']).count("campaign:live_chat:#{live_chat.id}")).to eq(1)
    expect(plain.reload.additional_attributes.to_h['campaign']).to be_nil
  end
end
