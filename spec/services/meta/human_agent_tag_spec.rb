require 'rails_helper'

RSpec.describe Meta::HumanAgentTag do
  let(:config_key) { 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT' }
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }

  def customer_wrote(time_ago)
    travel_to(time_ago.ago) { create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :incoming) }
  end

  def reply(sender: agent, **attrs)
    create(:message, conversation: conversation, account: account, inbox: conversation.inbox, message_type: :outgoing,
                     sender: sender, **attrs)
  end

  def flag(value)
    InstallationConfig.where(name: config_key).delete_all
    InstallationConfig.create!(name: config_key, value: value, locked: false)
    GlobalConfig.clear_cache
  end

  before { flag(true) }

  context 'when the customer wrote more than 24 hours ago' do
    before { customer_wrote(30.hours) }

    it 'tags a reply typed by a person of the team' do
      expect(described_class.apply?(reply, config_key)).to be(true)
    end

    it 'does not tag when the flag is off' do
      flag(false)

      expect(described_class.apply?(reply, config_key)).to be(false)
    end

    it 'does not tag a bot reply' do
      expect(described_class.apply?(reply(sender: create(:agent_bot, account: account)), config_key)).to be(false)
    end

    it 'does not tag an AI follow-up saved in the name of a person (crm_follow_up_id)' do
      message = reply(content_attributes: { 'crm_follow_up_id' => 1 })

      expect(described_class.apply?(message, config_key)).to be(false)
    end

    it 'does not tag an automation rule message' do
      expect(described_class.apply?(reply(sender: nil, content_attributes: { 'automation_rule_id' => 1 }), config_key)).to be(false)
    end

    it 'does not tag a campaign message' do
      expect(described_class.apply?(reply(additional_attributes: { 'campaign_id' => 1 }), config_key)).to be(false)
    end

    it 'does not tag a message sent by an integration user' do
      bot_user = create(:user)
      create(:account_user, account: account, user: bot_user, integration: true)

      expect(described_class.apply?(reply(sender: bot_user), config_key)).to be(false)
    end

    it 'does not tag a private note' do
      expect(described_class.apply?(reply(private: true), config_key)).to be(false)
    end
  end

  it 'does not tag a person reply inside the 24 hours window' do
    customer_wrote(2.hours)

    expect(described_class.apply?(reply, config_key)).to be(false)
  end

  it 'does not tag when the customer never wrote' do
    expect(described_class.apply?(reply, config_key)).to be(false)
  end
end
