require 'rails_helper'

# chat#1021: text the fork already rendered keeps literal; every other outgoing message still goes
# through Chatwoot's Liquid pass.
RSpec.describe Autonomia::LiteralMessageContent do
  let(:contact) { create(:contact, name: 'john') }
  let(:conversation) { create(:conversation, contact: contact) }

  def create_outgoing(content, **attributes)
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                     message_type: 'outgoing', content: content, **attributes)
  end

  def template_params(value)
    { 'template_params' => { 'name' => 'retorno', 'language' => 'pt_BR', 'processed_params' => { '1' => value } } }
  end

  it 'is prepended into Message' do
    expect(Message.ancestors).to include(described_class)
  end

  context 'when the fork marked the content as already rendered' do
    it 'keeps a value with {{ }} literal' do
      message = create_outgoing('Olá {{publico.plano}} Ana', literal_content: true)

      expect(message.reload.content).to eq('Olá {{publico.plano}} Ana')
    end

    it 'keeps a value with {% %} literal' do
      message = create_outgoing('Olá {% if true %}x{% endif %}', literal_content: true)

      expect(message.reload.content).to eq('Olá {% if true %}x{% endif %}')
    end

    it 'does not persist the mark' do
      message = create_outgoing('Olá', literal_content: true)

      expect(Message.find(message.id).literal_content).to be_nil
      expect(message.reload.content_attributes).not_to have_key('literal_content')
    end
  end

  context 'when the fork marked the template params as final values' do
    it 'keeps them literal and still renders the content' do
      message = create_outgoing('hey {{contact.name}}', additional_attributes: template_params('{{publico.plano}} Ana'),
                                                        literal_template_params: true)

      expect(message.reload.additional_attributes.dig('template_params', 'processed_params', '1')).to eq('{{publico.plano}} Ana')
      expect(message.content).to eq('hey John')
    end
  end

  context 'when the message is not marked' do
    it 'still renders a {{contact.name}} the agent typed' do
      message = create_outgoing('hey {{contact.name}} how are you?')

      expect(message.reload.content).to eq('hey John how are you?')
    end

    it 'ignores a literal_content key sent in content_attributes' do
      message = create_outgoing('hey {{contact.name}}', content_attributes: { 'literal_content' => true })

      expect(message.reload.content).to eq('hey John')
    end

    it 'still renders template params' do
      message = create_outgoing('Olá', additional_attributes: template_params('{{contact.name}}'))

      expect(message.reload.additional_attributes.dig('template_params', 'processed_params', '1')).to eq('John')
    end

    it 'does not touch incoming messages' do
      message = create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                                 message_type: 'incoming', content: 'hey {{contact.name}}')

      expect(message.reload.content).to eq('hey {{contact.name}}')
    end
  end
end
