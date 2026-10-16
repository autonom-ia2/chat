require 'rails_helper'

# chat#1709 (fase 3): o que o conector c2y-rich-2 acrescenta à mensagem que ele cria na caixa WAHA comum. Com a flag,
# vira a apresentação nova; sem ela, só a chave sai e a mensagem fica igual à da main.
describe Waha::RichNative::Inbound do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:agent) { create(:user, account: account, role: :administrator) }

  before { account.update!(locale: 'pt_BR') }

  def flag_on!
    account.enable_features!(Waha::RichNative::FLAG)
  end

  def from_connector(attributes, message_type: :incoming, private: false, content: 'texto do conector', sender: nil)
    create(:message, message_type: message_type, private: private, content: content, conversation: conversation, inbox: inbox,
                     account: account, sender: sender || (message_type == :incoming ? conversation.contact : agent),
                     content_attributes: attributes).reload
  end

  describe 'calls (waha_call)' do
    def call(event, extra = {})
      data = { call_id: 'C1', event: event, is_video: false, by_me: false, reason: nil }.merge(extra)
      from_connector({ waha_call: data }, content: 'Chamada de voz recebida')
    end

    it 'keeps the message of main without the flag, dropping the key' do
      message = call('received')

      expect(message).to be_incoming
      expect(message.content).to eq('Chamada de voz recebida')
      expect(message.content_attributes).not_to have_key('waha_call')
    end

    it 'turns the ring into a hidden activity and an unanswered call into a missed-call notice' do
      flag_on!
      ring = call('received')
      missed = call('rejected', reason: 'timeout')

      expect(ring).to be_activity
      expect(ring.content_attributes).to include('c2y_hidden' => true)
      expect(missed).to be_activity
      expect(missed.content).to eq('Ligação de voz perdida')
      expect(missed.content_attributes['waha_call_summary']).to eq('call_id' => 'C1', 'outcome' => 'missed', 'is_video' => false)
    end

    it 'tells declined, answered and ended calls apart, video included' do
      flag_on!

      expect(call('rejected', by_me: true, is_video: true).content).to eq('Chamada de vídeo recusada')
      expect(call('accepted', call_id: 'C2').content).to eq('Ligação atendida no celular')
      expect(call('rejected', call_id: 'C2').content).to eq('Ligação encerrada')
    end

    it 'never reaches the AI or the inbox webhook' do
      flag_on!
      allow(WebhookJob).to receive(:perform_later)

      message = call('rejected')

      expect(message.webhook_sendable?).to be(false)
      expect(conversation.reload.messages.incoming).to be_empty
    end
  end

  describe 'unknown messages (waha_unknown)' do
    def unknown(from_me: false)
      from_connector({ waha_unknown: { content_type: 'eventMessage', from_me: from_me } },
                     message_type: :outgoing, private: true, content: 'Mensagem não suportada (job 1)')
    end

    it 'keeps the private note of main without the flag' do
      note = unknown

      expect(note).to be_outgoing
      expect(note.private).to be(true)
      expect(note.content).to eq('Mensagem não suportada (job 1)')
      expect(note.content_attributes).not_to have_key('waha_unknown')
    end

    it 'becomes a short customer bubble with the flag' do
      flag_on!
      message = unknown

      expect(message).to be_incoming
      expect(message.private).to be(false)
      expect(message.sender).to eq(conversation.contact)
      expect(message.content).to eq(I18n.t('conversations.messages.whatsapp.unsupported_message', locale: 'pt_BR'))
      expect(message.content_attributes).to include('is_unsupported' => true, 'waha_unknown_type' => 'eventMessage')
    end

    it 'keeps the note when it came from the company phone' do
      flag_on!
      expect(unknown(from_me: true)).to be_outgoing
    end
  end

  describe 'reactions (waha_reaction)' do
    let(:original) do
      create(:message, message_type: :outgoing, content: 'Até amanhã', conversation: conversation, inbox: inbox, account: account,
                       sender: agent)
    end

    def reaction(emoji, from_me: false)
      from_connector({ in_reply_to: original.id, waha_reaction: { emoji: emoji, reacted_wa_id: 'W1', from_me: from_me } },
                     content: emoji.present? ? "*Reagiu com* #{emoji}" : '*Reação removida*')
    end

    it 'keeps the new bubble of main without the flag' do
      message = reaction('👍')

      expect(message).to be_incoming
      expect(message.content).to eq('*Reagiu com* 👍')
      expect(original.reload.content_attributes).not_to have_key('reactions')
    end

    it 'sticks the reaction to the original, replaces and removes it, without a new bubble' do
      flag_on!
      first = reaction('👍')
      reaction('😂')
      reaction('❤️', from_me: true)

      expect(first).to be_activity
      expect(first.content_attributes).to include('c2y_hidden' => true, 'reaction_applied_to' => original.id)
      expect(original.reload.content_attributes['reactions'].map { |item| item.slice('emoji', 'by') })
        .to eq([{ 'emoji' => '😂', 'by' => 'contact' }, { 'emoji' => '❤️', 'by' => 'phone' }])

      reaction('')
      expect(original.reload.content_attributes['reactions'].pluck('by')).to eq(['phone'])
      expect(conversation.messages.incoming).to be_empty
    end
  end

  describe 'edits (waha_edit)' do
    let(:original) do
      create(:message, message_type: :incoming, content: 'Chego às 10', conversation: conversation, inbox: inbox, account: account,
                       sender: conversation.contact)
    end

    def edited(text, from_me: false, target: original)
      from_connector({ in_reply_to: target.id, waha_edit: { text: text, edited_wa_id: 'W2', from_me: from_me } },
                     content: "#{text}\n\n✏️ *Editado no WhatsApp*")
    end

    it 'keeps the new bubble of main without the flag' do
      message = edited('Chego às 11')

      expect(message).to be_incoming
      expect(original.reload.content).to eq('Chego às 10')
    end

    it 'replaces the text of the original, keeping the previous one, without a new bubble' do
      flag_on!
      message = edited('Chego às 11')

      expect(message).to be_activity
      expect(message.content_attributes).to include('c2y_hidden' => true, 'edit_applied_to' => original.id)
      original.reload
      expect(original.content).to eq('Chego às 11')
      expect(original.content_attributes['edit_history'].sole).to include('content' => 'Chego às 10', 'by' => 'contact')
      expect(original.content_attributes['edited_at']).to be_present
    end

    it 'only edits a message in the same direction' do
      flag_on!
      message = edited('Outro texto', from_me: true)

      expect(message).to be_incoming
      expect(original.reload.content).to eq('Chego às 10')
    end
  end

  it 'never lets an error stop the creation, and leaves the message as main' do
    flag_on!
    allow(Waha::RichNative::Inbound::Call).to receive(:apply).and_raise(StandardError)

    message = from_connector({ waha_call: { call_id: 'C9', event: 'received' } }, content: 'Chamada de voz recebida')

    expect(message).to be_incoming
    expect(message.content_attributes).not_to have_key('waha_call')
  end

  it 'only drops the keys in another kind of inbox' do
    flag_on!
    other = create(:inbox, account: account)
    other_conversation = create(:conversation, inbox: other, account: account)
    message = create(:message, message_type: :incoming, content: 'oi', conversation: other_conversation, inbox: other,
                               account: account, content_attributes: { waha_call: { call_id: 'X', event: 'received' } })

    expect(message.reload).to be_incoming
    expect(message.content_attributes).not_to have_key('waha_call')
  end
end
