require 'rails_helper'

# #2277: the text each reader gets — who spoke, without private notes, capped by the most recent messages.
RSpec.describe ConversationAudience::Transcript do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def say(content, type: :incoming, **attributes)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: type, content: content, **attributes)
  end

  it 'labels the customer, a person of the team and the automation, and leaves private notes out' do
    say('Quanto fica para 2 pessoas?')
    say('Já te mando', type: :outgoing)
    say('Nota interna', type: :outgoing, private: true)
    create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation, content: 'Mensagem automática')

    text = described_class.new(account).for([conversation.id])[conversation.id]

    expect(text).to start_with("=== CONVERSA #{conversation.id} | criada ")
    expect(text).to include('CLIENTE: Quanto fica para 2 pessoas?', 'EQUIPE: Já te mando', 'ASSISTENTE: Mensagem automática')
    expect(text).not_to include('Nota interna')
  end

  it 'keeps the most recent messages when the conversation is longer than one reader call' do
    say('primeira mensagem')
    say('x' * described_class::MAX_CHARS)
    say('última mensagem')

    text = described_class.new(account).for([conversation.id])[conversation.id]

    expect(text).to include('última mensagem')
    expect(text).not_to include('primeira mensagem')
    expect(text.size).to be <= described_class::MAX_CHARS
  end

  it 'leaves out a conversation without messages and one of another account' do
    other = create(:conversation)
    create(:message, account: other.account, inbox: other.inbox, conversation: other, content: 'de outra conta')
    empty = create(:conversation, account: account, inbox: inbox)

    expect(described_class.new(account).for([empty.id, other.id])).to eq({})
  end
end
