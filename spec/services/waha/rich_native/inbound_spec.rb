require 'rails_helper'

# chat#1709 (fase 3): o que o conector c2y-rich-2 acrescenta à mensagem que ele cria na caixa WAHA comum. Com a flag,
# vira a apresentação nova; sem ela, só a chave sai e a mensagem fica igual à da main. Só o conector (o dono do token
# da caixa) pode mandar as chaves.
describe Waha::RichNative::Inbound do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    account.update!(locale: 'pt_BR')
    channel.update!(additional_attributes: channel.additional_attributes.merge('account_token_owner_user_id' => connector.id))
  end

  after { Current.reset }

  def flag_on!
    account.enable_features!(Waha::RichNative::FLAG)
  end

  # options: message_type (:incoming), private, content, user (quem chama a API: o conector) e target_conversation.
  def from_connector(attributes, **options)
    message_type = options.fetch(:message_type, :incoming)
    target_conversation = options.fetch(:target_conversation, conversation)
    Current.user = options.fetch(:user, connector)
    create(:message, message_type: message_type, private: options.fetch(:private, false), inbox: inbox, account: account,
                     content: options.fetch(:content, 'texto do conector'), conversation: target_conversation,
                     sender: message_type == :incoming ? target_conversation.contact : connector, content_attributes: attributes).reload
  ensure
    Current.user = nil
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

    it 'shows the ring as one call line and turns an unanswered call into a missed call on the same line' do
      flag_on!
      ring = call('received')
      missed = call('rejected', reason: 'timeout')

      expect(ring).to be_activity
      expect(ring.content).to eq('Ligação de voz recebida')
      expect(ring.content_attributes).not_to have_key('c2y_hidden')
      expect(ring.reload.content).to eq('Ligação de voz perdida')
      expect(ring.content_attributes['waha_call_summary']).to include('call_id' => 'C1', 'outcome' => 'missed', 'is_video' => false,
                                                                      'at' => a_kind_of(String))
      expect(missed).to be_activity
      expect(missed.content_attributes).to include('c2y_hidden' => true)
    end

    it 'keeps the ring visible when the phone answers elsewhere and no outcome arrives' do
      flag_on!
      ring = call('received', is_video: true)

      expect(ring.reload.content).to eq('Ligação de vídeo recebida')
      expect(described_class.hidden?(ring)).to be(false)
    end

    it 'tells declined, answered and ended calls apart, video included' do
      flag_on!

      declined = call('rejected', by_me: true, is_video: true, call_id: 'C3')
      expect(declined.content).to eq('Ligação de vídeo recusada')
      expect(declined.content_attributes['waha_call_summary']).to include('outcome' => 'rejected', 'is_video' => true)
      answered = call('accepted', call_id: 'C2')
      expect(answered.content).to eq('Ligação atendida no celular')
      expect(answered.content_attributes['waha_call_summary']).to include('outcome' => 'accepted')
      expect(answered.content_attributes['waha_call_summary']).not_to have_key('ended')
      call('rejected', call_id: 'C2')
      expect(answered.reload.content).to eq('Ligação atendida e encerrada')
      expect(answered.content_attributes['waha_call_summary']).to include('outcome' => 'accepted', 'ended' => true)
    end

    it 'keeps the transitory ringing outcome while the call rings' do
      flag_on!
      expect(call('received', call_id: 'C5').content_attributes['waha_call_summary']).to include('outcome' => 'ringing')
    end

    it 'does not turn a late ring back into a received call' do
      flag_on!
      missed = call('rejected', call_id: 'C4')
      late = call('received', call_id: 'C4')

      expect(missed.reload.content).to eq('Ligação de voz perdida')
      expect(late.content_attributes).to include('c2y_hidden' => true)
    end

    it 'never reaches the AI or the inbox webhook' do
      flag_on!

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
      expect(message.content_attributes).to include('is_unsupported' => true, 'unsupported_kind' => 'unknown')
      expect(message.content_attributes).not_to have_key('waha_unknown_type')
    end

    it 'records the kind when the engine knows it (exact table, gif flag), unknown otherwise' do
      flag_on!
      kinds = { 'pollCreationMessageV3' => 'poll', 'pinInChatMessage' => 'pinned', 'editedMessage' => 'edit',
                'viewOnceMessageV2' => 'view_once', 'eventMessage' => 'unknown', nil => 'unknown' }
      kinds.each do |content_type, kind|
        message = from_connector({ waha_unknown: { content_type: content_type, from_me: false } }, message_type: :outgoing, private: true)
        expect(message.content_attributes['unsupported_kind']).to eq(kind), content_type.inspect
      end
      gif = from_connector({ waha_unknown: { content_type: 'videoMessage', gif: true, from_me: false } }, message_type: :outgoing, private: true)
      expect(gif.content_attributes['unsupported_kind']).to eq('gif')
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

    def reaction(emoji, from_me: false, target: original, **)
      from_connector({ in_reply_to: target.id, waha_reaction: { emoji: emoji, reacted_wa_id: 'W1', from_me: from_me } },
                     content: emoji.present? ? "*Reagiu com* #{emoji}" : '*Reação removida*', **)
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
      expect(first.content).to eq('Reação registrada na mensagem')
      expect(first.content_attributes).to include('c2y_hidden' => true, 'reaction_applied_to' => original.id)
      expect(original.reload.content_attributes['reactions'].map { |item| item.slice('emoji', 'sender_type', 'sender_id') })
        .to eq([{ 'emoji' => '😂', 'sender_type' => 'Contact', 'sender_id' => conversation.contact_id },
                { 'emoji' => '❤️', 'sender_type' => 'User', 'sender_id' => nil }])

      reaction('')
      expect(original.reload.content_attributes['reactions'].pluck('sender_type')).to eq(['User'])
      reaction('', from_me: true)
      expect(original.reload.content_attributes).not_to have_key('reactions')
      expect(conversation.messages.incoming).to be_empty
    end

    it 'treats the company phone and the panel as the same author (one business reaction)' do
      flag_on!
      Waha::RichNative::Reactions.apply!(original, emoji: '👍', author: Waha::RichNative::Reactions.business_author(agent.id))

      reaction('❤️', from_me: true)

      expect(original.reload.content_attributes['reactions'].map { |item| item.slice('emoji', 'sender_type', 'sender_id') })
        .to eq([{ 'emoji' => '❤️', 'sender_type' => 'User', 'sender_id' => nil }])
    end

    it 'applies to the original in an older conversation of the same contact and still hides the new message' do
      flag_on!
      newer = create(:conversation, inbox: inbox, account: account, contact: conversation.contact,
                                    contact_inbox: conversation.contact_inbox)

      message = reaction('👍', target_conversation: newer)

      expect(message).to be_activity
      expect(message.content_attributes['c2y_hidden']).to be(true)
      expect(original.reload.content_attributes['reactions'].pluck('emoji')).to eq(['👍'])
    end

    it 'does not touch a message of another contact, a private note or a failed message' do
      flag_on!
      stranger = create(:conversation, inbox: inbox, account: account)
      foreign = create(:message, message_type: :outgoing, content: 'outro', conversation: stranger, inbox: inbox, account: account)
      note = create(:message, message_type: :outgoing, private: true, content: 'nota', conversation: conversation, inbox: inbox,
                              account: account, sender: agent)
      failed = create(:message, message_type: :outgoing, content: 'falhou', conversation: conversation, inbox: inbox,
                                account: account, sender: agent, status: :failed,
                                content_attributes: { external_error: 'timeout' })

      [foreign, note, failed].each do |target|
        expect(reaction('👍', target: target)).to be_incoming
        expect(target.reload.content_attributes).not_to have_key('reactions')
      end
    end
  end

  describe 'edits (waha_edit)' do
    let(:original) do
      create(:message, message_type: :incoming, content: 'Chego às 10', conversation: conversation, inbox: inbox, account: account,
                       sender: conversation.contact)
    end

    def edited(text, from_me: false, target: original, **)
      from_connector({ in_reply_to: target.id, waha_edit: { text: text, edited_wa_id: 'W2', from_me: from_me } },
                     content: "#{text}\n\n✏️ *Editado no WhatsApp*", **)
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
      expect(message.content).to eq('Edição registrada na mensagem')
      expect(message.content_attributes).to include('c2y_hidden' => true, 'edit_applied_to' => original.id)
      original.reload
      expect(original.content).to eq('Chego às 11')
      expect(original.content_attributes['edit_history'].sole)
        .to include('content' => 'Chego às 10', 'sender_type' => 'Contact', 'sender_id' => conversation.contact_id)
      expect(original.content_attributes['edited_at']).to be_present
    end

    # Rodada de correção, item 17 (com o C2 do conector c2y-rich-5): a edição traz a hora do WhatsApp; uma que chega
    # depois de outra mais nova não volta o texto.
    it 'applies an edit only when its WhatsApp time is not older than the last stored one' do
      flag_on!
      at = Time.zone.parse('2026-10-16 10:00:00')
      edit = lambda do |text, time|
        from_connector({ in_reply_to: original.id, waha_edit: { text: text, edited_wa_id: 'W2', from_me: false, timestamp: time.to_i } },
                       content: text)
      end

      edit.call('Chego às 12', at + 60)
      late = edit.call('Chego às 11', at)

      expect(late).to be_activity
      original.reload
      expect(original.content).to eq('Chego às 12')
      expect(original.content_attributes['edited_at']).to eq((at + 60).iso8601)
      expect(original.content_attributes['edit_history'].pluck('content')).to eq(['Chego às 10'])

      edit.call('Chego às 13', at + 120)
      expect(original.reload.content).to eq('Chego às 13')
    end

    it 'records an edit from the company phone as User without sender_id' do
      flag_on!
      ours = create(:message, message_type: :outgoing, content: 'Até 10h', conversation: conversation, inbox: inbox, account: account,
                              sender: agent)

      edited('Até 11h', from_me: true, target: ours)

      expect(ours.reload.content_attributes['edit_history'].sole).to include('sender_type' => 'User', 'sender_id' => nil)
    end

    it 'only edits a message in the same direction' do
      flag_on!
      message = edited('Outro texto', from_me: true)

      expect(message).to be_incoming
      expect(original.reload.content).to eq('Chego às 10')
    end

    it 'refuses a text above the WhatsApp limit and keeps only the latest edits in the history' do
      flag_on!
      expect(edited('x' * (Waha::RichNative::Edits::MAX_LENGTH + 1))).to be_incoming

      (Waha::RichNative::Edits::HISTORY_LIMIT + 2).times { |index| edited("versão #{index}") }

      history = original.reload.content_attributes['edit_history']
      expect(history.size).to eq(Waha::RichNative::Edits::HISTORY_LIMIT)
      expect(history.last['content']).to eq("versão #{Waha::RichNative::Edits::HISTORY_LIMIT}")
    end
  end

  describe 'poll votes with the flag turned off later (waha_poll_vote)' do
    it 'hides the vote instead of a plain "Sim" the AI would answer (main never gets the vote)' do
      vote = from_connector({ waha_poll_vote: { poll_message_id: 1, options: ['Sim'], vote_id: 'V1', timestamp: 1 } }, content: 'Sim')

      expect(vote).to be_activity
      expect(vote.content_attributes).to include('c2y_hidden' => true)
      expect(vote.content_attributes).not_to have_key('waha_poll_vote')
    end
  end

  describe 'forgery: only the connector can send the keys' do
    let(:original) do
      create(:message, message_type: :incoming, content: 'Chego às 10', conversation: conversation, inbox: inbox, account: account,
                       sender: conversation.contact)
    end
    let(:keys) do
      {
        waha_poll_vote: { poll_message_id: original.id, options: ['Sim'], vote_id: 'V', timestamp: 1 },
        waha_call: { call_id: 'F', event: 'received' },
        waha_unknown: { content_type: 'x', from_me: false },
        waha_reaction: { emoji: '👍', reacted_wa_id: 'W', from_me: false },
        waha_edit: { text: 'texto forjado', edited_wa_id: 'W', from_me: false }
      }
    end

    before { flag_on! }

    it 'drops each key from another agent without touching any message' do
      keys.each do |key, data|
        message = from_connector({ 'in_reply_to' => original.id, key.to_s => data }, message_type: :outgoing, content: 'nota', user: agent)

        expect(message).to be_outgoing, key.to_s
        expect(message.content).to eq('nota')
        expect(message.content_attributes).not_to have_key(key.to_s)
        expect(message.content_attributes).not_to have_key('c2y_hidden')
      end
      expect(original.reload.content).to eq('Chego às 10')
      expect(original.content_attributes).not_to have_key('reactions')
    end

    it 'accepts an administrator when the inbox has no token owner recorded, never a plain agent' do
      channel.update!(additional_attributes: channel.additional_attributes.except('account_token_owner_user_id'))
      data = { in_reply_to: original.id, waha_edit: { text: 'Chego às 11', edited_wa_id: 'W', from_me: false } }

      expect(from_connector(data, user: agent)).to be_incoming
      expect(original.reload.content).to eq('Chego às 10')
      expect(from_connector(data, user: connector)).to be_activity
      expect(original.reload.content).to eq('Chego às 11')
    end
  end

  describe 'hidden activity' do
    it 'does not move the conversation up in the list' do
      flag_on!
      original = create(:message, message_type: :outgoing, content: 'Até', conversation: conversation, inbox: inbox, account: account)
      earlier = 1.hour.ago.change(usec: 0)
      conversation.update_columns(last_activity_at: earlier) # rubocop:disable Rails/SkipsModelValidations

      reaction = from_connector({ in_reply_to: original.id, waha_reaction: { emoji: '👍', reacted_wa_id: 'W1', from_me: false } })

      expect(reaction).to be_activity
      expect(conversation.reload.last_activity_at).to eq(earlier)
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
    Current.user = connector
    message = create(:message, message_type: :incoming, content: 'oi', conversation: other_conversation, inbox: other,
                               account: account, content_attributes: { waha_call: { call_id: 'X', event: 'received' } })

    expect(message.reload).to be_incoming
    expect(message.content_attributes).not_to have_key('waha_call')
  end
end
