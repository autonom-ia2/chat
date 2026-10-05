require 'rails_helper'

# chat#1021: an outgoing message the fork already rendered keeps its content literal; every other
# outgoing message still goes through Chatwoot's Liquid pass.
RSpec.describe Autonomia::LiteralMessageContent do
  let(:contact) { create(:contact, name: 'john') }
  let(:conversation) { create(:conversation, contact: contact) }

  def create_outgoing(content, content_attributes = {})
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                     message_type: 'outgoing', content: content, content_attributes: content_attributes)
  end

  it 'is prepended into Message' do
    expect(Message.ancestors).to include(described_class)
  end

  context 'when the fork marked the content as already rendered' do
    it 'keeps a value with {{ }} literal' do
      message = create_outgoing('Olá {{publico.plano}} Ana', described_class.attributes)

      expect(message.reload.content).to eq('Olá {{publico.plano}} Ana')
    end

    it 'keeps a value with {% %} literal' do
      message = create_outgoing('Olá {% if true %}x{% endif %}', described_class.attributes)

      expect(message.reload.content).to eq('Olá {% if true %}x{% endif %}')
    end

    it 'keeps the mark in content_attributes' do
      message = create_outgoing('Olá', described_class.attributes)

      expect(message.reload.content_attributes[described_class::FLAG]).to be(true)
    end
  end

  context 'when the message is not marked' do
    it 'still renders a {{contact.name}} the agent typed' do
      message = create_outgoing('hey {{contact.name}} how are you?')

      expect(message.reload.content).to eq('hey John how are you?')
    end

    it 'still renders Liquid when the mark is not exactly true' do
      message = create_outgoing('hey {{contact.name}}', { described_class::FLAG => 'false' })

      expect(message.reload.content).to eq('hey John')
    end

    it 'does not touch incoming messages' do
      message = create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                                 message_type: 'incoming', content: 'hey {{contact.name}}')

      expect(message.reload.content).to eq('hey {{contact.name}}')
    end
  end
end
