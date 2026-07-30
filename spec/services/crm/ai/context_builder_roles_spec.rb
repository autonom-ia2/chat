require 'rails_helper'

RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline,
      stage: stage,
      title: 'Lead',
      contact: contact,
      primary_conversation: conversation,
      currency: 'BRL'
    )
  end

  def add_message(content:, type:, sender: nil, target: nil)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: target || conversation,
      content: content,
      message_type: type,
      sender: sender
    )
  end

  it 'distinguishes customer, human agent, platform agent and external agent' do
    platform_bot = create(:agent_bot, account: account)
    external_bot = create(:agent_bot, account: account)
    Autonomia::Agents::AgentInbox.create!(
      account: account,
      agent: Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'sdr'),
      inbox: inbox,
      agent_bot: platform_bot
    )

    add_message(content: 'quero cotar', type: :incoming, sender: contact)
    add_message(content: 'te ajudo agora', type: :outgoing, sender: admin)
    add_message(content: 'segue a proposta', type: :outgoing, sender: platform_bot)
    add_message(content: 'integracao externa', type: :outgoing, sender: external_bot)

    roles = described_class.new(card: card).perform[:recent_messages].map { |m| m[:role] }

    expect(roles).to eq(%w[customer human_agent platform_agent external_agent])
  end

  it 'reads messages from linked conversations, not only the primary one' do
    other = create_crm_conversation(account: account, inbox: inbox, contact: contact)
    card.card_conversations.create!(account: account, conversation: other)

    add_message(content: 'primeira conversa', type: :incoming, sender: contact)
    add_message(content: 'segunda conversa', type: :incoming, sender: contact, target: other)

    messages = described_class.new(card: card).perform[:recent_messages]

    expect(messages.map { |m| m[:content] }).to contain_exactly('primeira conversa', 'segunda conversa')
    expect(messages.map { |m| m[:conversation_id] }).to contain_exactly(conversation.id, other.id)
  end
end
