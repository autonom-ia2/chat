require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (rodada 2): os achados da revisão independente. Cada caso é a falha que ela apontou.
describe 'WAHA rich native round 2 review' do # rubocop:disable RSpec/DescribeClass
  include_context 'with a waha inbox and its connector'

  let(:ogg) { { filename: 'no-filename.oga', content_type: 'audio/ogg', file_type: :audio } }

  describe 'stored keys with generic names (ContractGuard and ForgeryGuard)' do
    it 'keeps them in a Channel::Api inbox of another provider, and drops the internal marks everywhere' do
      other = create(:channel_api, account: account).inbox
      other_conversation = create(:conversation, inbox: other, account: account)
      message = other_conversation.messages.create!(
        account: account, inbox: other, message_type: :incoming, content: 'oi', sender: other_conversation.contact,
        content_attributes: { 'forwarded' => true, 'quoted_message' => { 'content' => 'x' }, 'c2y_hidden' => true,
                              'reaction_applied_to' => 1, 'waha_call_summary' => {} }
      )

      expect(message.reload.content_attributes).to include('forwarded' => true, 'quoted_message' => { 'content' => 'x' })
      expect(message.content_attributes.keys & %w[c2y_hidden reaction_applied_to waha_call_summary]).to eq([])
    end

    # Rodada de correção, item 1: o recebimento da Cloud e o encaminhamento do #1702b gravam as chaves de nome genérico
    # por dentro, na criação. O callback do modelo não as tira (só a API pública, Waha::RichNative::ForgeryGuard).
    context 'when the chat2you itself creates the message (no public API)' do
      let(:generic) do
        Waha::RichNative::ContractGuard::SCOPED_KEYS.index_with { |key| "valor de #{key}" }
                                                    .merge('is_unsupported' => true)
      end
      let(:cloud) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
      end

      def create_in(target_inbox, **attributes)
        target = create(:conversation, inbox: target_inbox, account: account)
        target.messages.create!(account: account, inbox: target_inbox, message_type: :incoming, content: 'oi', sender: target.contact,
                                content_attributes: attributes)
      end

      it 'keeps every generic key, without the flag, as the main stores it (WAHA and WhatsApp inboxes)' do
        expect(create_in(inbox, **generic).reload.content_attributes).to eq(generic)
        expect(create_in(cloud, **generic).reload.content_attributes).to eq(generic)
      end

      it 'keeps them with the flag too, and keeps the forwarded mark of an outgoing message built by the MessageBuilder' do
        flag_on!
        expect(create_in(cloud, **generic).reload.content_attributes).to eq(generic)

        target = create(:conversation, inbox: cloud, account: account)
        params = ActionController::Parameters.new(content: 'encaminhada', message_type: 'outgoing', private: false,
                                                  content_attributes: { 'forwarded' => true, 'forwarded_from' => { 'message_id' => 1 } })
        message = Messages::MessageBuilder.new(agent, target, params).perform

        expect(message.reload.content_attributes).to include('forwarded' => true, 'forwarded_from' => { 'message_id' => 1 })
      end

      it 'still drops the internal marks and the connector requests' do
        message = create_in(cloud, 'c2y_hidden' => true, 'waha_native' => {}, 'c2y_ai_turn' => {}, 'forwarded' => true)

        expect(message.reload.content_attributes).to eq('forwarded' => true)
      end
    end
  end

  describe 'attachment marks (AttachmentMeta)' do
    it 'keeps the JSON of main for a panel voice note outside the WAHA inbox or without the flag' do
      cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false,
                                        validate_provider_config: false).inbox
      flag_on!
      cloud_message = create(:message, account: account, inbox: cloud, conversation: create(:conversation, inbox: cloud, account: account))
      cloud_audio = cloud_message.attachments.create!(account: account, file_type: :audio, meta: { 'is_voice_message' => true },
                                                      file: { io: StringIO.new('x'), filename: 'v.ogg', content_type: 'audio/ogg' })
      expect(cloud_audio.push_event_data).not_to have_key(:meta)

      account.disable_features!(Waha::RichNative::FLAG)
      waha_message = create(:message, account: account, inbox: inbox, conversation: conversation)
      waha_audio = waha_message.attachments.create!(account: account, file_type: :audio, meta: { 'is_voice_message' => true },
                                                    file: { io: StringIO.new('x'), filename: 'v.ogg', content_type: 'audio/ogg' })
      expect(waha_audio.reload.push_event_data).not_to have_key(:meta)
    end
  end

  describe 'disappearing messages notice (Context.after_commit)' do
    it 'never raises after the customer message is saved, and the message stays unique' do
      flag_on!
      allow(Waha::RichNative::Inbound::Context).to receive(:notify!).and_raise(ActiveRecord::RecordInvalid)

      expect { from_connector({ waha_context: { ephemeral_expiration: 86_400 } }, content: 'oi') }.not_to raise_error
      expect(conversation.reload.messages.incoming.count).to eq(1)
    end

    it 'saves the notice even when the conversation is busy (no flooding validation)' do
      flag_on!
      allow_any_instance_of(Message).to receive(:prevent_message_flooding) do |message| # rubocop:disable RSpec/AnyInstance
        message.errors.add(:base, 'Too many messages') if message.activity?
      end

      from_connector({ waha_context: { ephemeral_expiration: 86_400 } }, content: 'oi')

      expect(conversation.reload.messages.activity.sole.content_attributes).to have_key('waha_ephemeral')
    end
  end

  # Rodada de correção, item 7: o aviso grava só a chave do tempo, sem regravar o resto a partir de uma cópia velha.
  describe 'the disappearing time on the conversation (Context.notify!)' do
    it 'keeps what another writer stored on the conversation after it was loaded' do
      stale = Conversation.find(conversation.id)
      Conversation.where(id: conversation.id).update_all(additional_attributes: { 'autonomia_debounce' => { 'pending_message_id' => 9 } }) # rubocop:disable Rails/SkipsModelValidations

      Waha::RichNative::Inbound::Context.notify!(stale, 86_400)

      expect(conversation.reload.additional_attributes).to include('autonomia_debounce' => { 'pending_message_id' => 9 },
                                                                   'c2y_ephemeral_expiration' => 86_400)
    end
  end

  # Revisão da rodada de correção, item 3: o tempo e o aviso vão juntos.
  describe 'the disappearing time and its notice in one transaction' do
    it 'does not store the new time when the notice cannot be saved' do
      allow(Waha::RichNative::InternalWrite).to receive(:mark!).and_raise(ActiveRecord::StatementInvalid, 'falhou')

      expect { Waha::RichNative::Inbound::Context.notify!(conversation, 86_400) }.to raise_error(ActiveRecord::StatementInvalid)

      expect(conversation.reload.additional_attributes).not_to have_key('c2y_ephemeral_expiration')
    end
  end

  # Rodada de correção, item 8: um erro de SQL num passo não aborta a criação da mensagem do cliente.
  describe 'a SQL error inside one step of the inbound' do
    it 'rolls back only that step and still saves the message with the other steps' do
      flag_on!
      allow(Waha::RichNative::Inbound::Context).to receive(:apply) do
        ActiveRecord::Base.connection.execute('SELECT * FROM c2y_tabela_que_nao_existe')
      end

      message = from_connector({ waha_context: { forwarded: true }, waha_unknown: { from_me: false, content_type: 'pollCreationMessage' } })

      expect(message).to be_persisted
      expect(message.content_attributes).to include('is_unsupported' => true, 'unsupported_kind' => 'poll')
    end
  end

  describe 'played receipt (PlayedReceipt.record!)' do
    it 'never raises when the lock fails' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)
      allow(message).to receive(:with_lock).and_raise(ActiveRecord::LockWaitTimeout)

      expect { Waha::RichNative::PlayedReceipt.record!(message, Time.current.iso8601) }.not_to raise_error
    end
  end

  describe 'quotes (Quote)' do
    before { flag_on! }

    it 'never copies a private note: it falls back to the unverified excerpt of the device' do
      note = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, private: true,
                              content: 'nota interna com https://waha.example/jobs/9')

      message = from_connector({ waha_quote: { wa_id: 'W1', body: 'o que o aparelho mostrou', chatwoot_message_id: note.id } })

      expect(message.content_attributes['quoted_message'])
        .to include('message_id' => nil, 'content' => 'o que o aparelho mostrou', 'unverified' => true)
      expect(message.content_attributes).not_to have_key('in_reply_to')
    end
  end

  # Enquete nativa nossa, gravada como o envio a deixa (a marca 'native' sai na criação pela API, por isso a coluna).
  def native_poll(options)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Prefere?').tap do |poll|
      attributes = { 'rich_message' => { 'type' => 'poll', 'options' => options }, 'rich_message_sent_as' => 'native' }
      poll.update_columns(content_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  describe 'event time (votes, event replies, reactions and calls)' do
    let(:poll) { native_poll([{ 'id' => 'a', 'title' => 'A' }, { 'id' => 'b', 'title' => 'B' }]) }

    it 'keeps the newer vote when a retried job brings an older one' do
      contact = conversation.contact
      Waha::RichNative::PollVotes.apply!(poll, sender: contact, titles: ['B'], timestamp: 1_760_000_200)
      Waha::RichNative::PollVotes.apply!(poll, sender: contact, titles: ['A'], timestamp: 1_760_000_100)

      vote = poll.reload.content_attributes['poll_votes'].sole
      expect(vote['options']).to eq(['B'])
      expect(vote['at']).to eq(Time.zone.at(1_760_000_200).iso8601)
    end

    it 'reads the event reply time in milliseconds and keeps the newer reply' do
      event = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Vistoria')
      contact = conversation.contact
      Waha::RichNative::EventResponses.apply!(event, sender: contact, response: 'going', timestamp: 1_760_000_200_000)
      Waha::RichNative::EventResponses.apply!(event, sender: contact, response: 'not_going', timestamp: 1_760_000_100_000)

      expect(event.reload.content_attributes['event_responses'].sole['response']).to eq('going')
    end

    it 'keeps the call time of the first event on the outcome' do
      flag_on!
      from_connector({ waha_call: { call_id: 'C1', event: 'received', is_video: false, timestamp: 1_760_000_000 } }, message_type: :incoming)
      line = conversation.reload.messages.activity.sole
      from_connector({ waha_call: { call_id: 'C1', event: 'rejected', is_video: false, by_me: false } }, message_type: :incoming)

      expect(line.reload.content_attributes['waha_call_summary']).to include('outcome' => 'missed', 'at' => Time.zone.at(1_760_000_000).iso8601)
    end
  end

  describe 'groups (poll and event)' do
    before do
      flag_on!
      conversation.contact.update!(identifier: '120363000000000000@g.us')
    end

    it 'never sends a poll or an event natively in a group' do
      allow(Waha::RichNative::WahaInbox).to receive(:types_for_inbox).and_return(%w[options poll event])

      with_modified_env(WAHA_RICH_NATIVE_ENGINES: 'https://waha.example/') do
        expect(Waha::RichNative::WahaInbox.native_types_for(conversation)).to eq(%w[options])
        conversation.contact.update!(identifier: '5511999990000@c.us')
        expect(Waha::RichNative::WahaInbox.native_types_for(conversation.reload)).to eq(%w[options poll event])
      end
    end

    it 'keeps a vote that reached a group as visible text instead of one voter for everyone' do
      poll = native_poll([{ 'id' => 'a', 'title' => 'A' }])
      expect(Waha::RichNative::PollVote.poll_for(poll.id, conversation_id: conversation.id, inbox_id: inbox.id)).to eq(poll)

      vote = from_connector({ waha_poll_vote: { poll_message_id: poll.id, options: ['A'] } }, content: 'A')

      expect(Waha::RichNative::Inbound.hidden?(vote)).to be(false)
      expect(poll.reload.content_attributes).not_to have_key('poll_votes')
    end
  end

  describe 'preview image of the link button (PreviewImage)' do
    let(:link) { { 'type' => 'link_button', 'label' => 'Ver', 'url' => 'https://exemplo.com.br/p' } }

    def create_link(image_url)
      Current.user = agent
      conversation.messages.create!(account: account, inbox: inbox, message_type: :outgoing, content: 'Segue', sender: agent,
                                    content_attributes: { 'rich_message' => link.merge('image_url' => image_url) })
    ensure
      Current.user = nil
    end

    it 'copies the external image through SafeFetch and keeps only the copy of this account' do
      flag_on!
      file = Tempfile.new('capa')
      file.write('img')
      file.rewind
      allow(SafeFetch).to receive(:fetch)
        .with('https://cdn.exemplo.com.br/capa.png', hash_including(schemes: %w[https], allowed_content_types: %w[image/jpeg image/png image/webp]))
        .and_yield(SafeFetch::Result.new(tempfile: file, filename: 'capa.png', content_type: 'image/png'))

      with_modified_env FRONTEND_URL: 'https://chat.exemplo.com.br' do
        image_url = create_link('https://cdn.exemplo.com.br/capa.png').reload.content_attributes.dig('rich_message', 'image_url')

        expect(image_url).to start_with('https://chat.exemplo.com.br/rails/active_storage/blobs/')
        expect(Waha::RichNative::PreviewImage.own(image_url, account)).to be_present
      end
    end

    it 'drops the field when the download is refused (private network), and does nothing without the flag' do
      allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::UnsafeUrlError)

      expect(create_link('https://10.0.0.1/a.png').reload.content_attributes['rich_message']).to have_key('image_url')
      expect(SafeFetch).not_to have_received(:fetch)

      flag_on!
      expect(create_link('https://10.0.0.1/a.png').reload.content_attributes['rich_message']).not_to have_key('image_url')
    end
  end

  describe 'event text in the account time zone' do
    it 'writes the Cloud text in the zone of the account, not the offset that came' do
      start_at = Time.find_zone('America/Sao_Paulo').now.advance(days: 2).change(hour: 14)
      message = Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Vistoria',
                            content_attributes: { 'rich_message' => { 'type' => 'event', 'start_at' => start_at.iso8601 } })
      flag_on!
      allow(Crm::Timezone::Resolver).to receive(:new).and_return(instance_double(Crm::Timezone::Resolver,
                                                                                 zone_or_default: ActiveSupport::TimeZone['Asia/Tokyo']))

      expect(RichMessages.build(message).fallback_text('Vistoria')).to eq("🕐 #{start_at.in_time_zone('Asia/Tokyo').strftime('%d/%m/%Y')} 02:00")
    end
  end

  # Decisão do Rodrigo (17/10/2026): a localização chega à IA só com nome e endereço (sem coordenadas nem link), no
  # formato do #1753; o cartão de contato chega com o telefone, da equipe ou do cliente.
  describe 'location and contact for the AI (ResponderLocation)' do
    let(:responder) { Autonomia::Agents::Operate::Responder.allocate }

    before do
      responder.instance_variable_set(:@conversation, conversation)
      # #1848: o histórico pergunta ao agente se as opções e o link são dele (Interacao.no_historico).
      responder.instance_variable_set(:@agent, criar_principal(conversation.account))
    end

    def ai_reads(message)
      allow(responder).to receive_messages(recent_messages: [message], last_incoming_message: message,
                                           equipe: instance_double(Autonomia::Agents::Operate::HistoricoDaEquipe, aplica?: false),
                                           media: Autonomia::Agents::Operate::MessageMedia::EMPTY)
      responder.send(:history).sole[:content]
    end

    def location_message(shared, content: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content,
                       sender: conversation.contact, content_attributes: { 'shared_location' => shared })
    end

    it 'gives the AI only the name and the address, never coordinates nor a map link, only with the flag' do
      message = location_message({ 'latitude' => -23.55, 'longitude' => -46.63, 'name' => 'Praça da Sé', 'address' => 'Centro' })
      expect(ai_reads(message)).to eq('')

      flag_on!
      expect(ai_reads(message)).to eq('Localização: Praça da Sé — Centro')
      expect(responder.send(:query)).to eq('Localização: Praça da Sé — Centro')
      expect(ai_reads(message)).not_to include('-23.55', 'maps', 'http')
    end

    it 'says when the location has neither name nor address' do
      flag_on!

      expect(ai_reads(location_message({ 'latitude' => 1.5, 'longitude' => 2.5 }))).to eq('Localização (sem nome nem endereço)')
    end

    it 'keeps the caption of a live location before the same text' do
      flag_on!
      message = location_message({ 'latitude' => 1.5, 'longitude' => 2.5, 'live' => true, 'name' => 'Casa' }, content: 'Estou chegando')

      content = ai_reads(message)
      expect(content).to eq("Estou chegando\nLocalização: Casa")
      expect(responder.send(:query)).to eq(content)
    end

    it 'gives the AI the phone of a contact card from the customer' do
      flag_on!
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                 content: 'Ana Souza', sender: conversation.contact,
                                 content_attributes: { 'shared_contacts' => [{ 'full_name' => 'Ana Souza', 'phones' => ['+55 11 98888-7777'],
                                                                               'wa_id' => '5511988887777' }] })

      expect(ai_reads(message)).to eq("Ana Souza\nContato: Ana Souza — +55 11 98888-7777")
    end

    it 'gives the AI the phone of a contact card sent by the team' do
      flag_on!
      card = { 'type' => 'contact', 'name' => 'Recepção', 'phone' => '+55 11 4000-0473' }
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: '',
                                 content_attributes: { 'rich_message' => card })

      expect(ai_reads(message)).to eq('Contato: Recepção — +55 11 4000-0473')
    end

    it 'follows the #1753 format: one line per contact, phone alone without a name, never the no-phone placeholder' do
      flag_on!
      contacts = [{ 'full_name' => 'Ana Souza', 'phones' => ['+55 11 98888-7777', '+55 11 3333-4444'] },
                  { 'full_name' => '', 'phones' => ['+55 21 97777-6666'] },
                  { 'full_name' => 'Bruno', 'phones' => ['Phone number is not available'] },
                  { 'full_name' => '', 'phones' => [] }]
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: nil,
                                 sender: conversation.contact, content_attributes: { 'shared_contacts' => contacts })

      expect(ai_reads(message)).to eq(['Contato: Ana Souza — +55 11 98888-7777, +55 11 3333-4444', 'Contato: +55 21 97777-6666',
                                       'Contato: Bruno', 'Contato (sem nome)'].join("\n"))
      expect(ai_reads(message)).not_to include('not available')
    end

    # Merge com o #1753: com a Fase 2, o histórico já sai do ResumoDaMensagemRica.texto; o resumo não entra duas vezes.
    it 'does not repeat the summary the team history (ResumoDaMensagemRica) already wrote; keeps adding it after a caption' do
      flag_on!
      resumo = Autonomia::Agents::Operate::ResumoDaMensagemRica
      sem_legenda = location_message({ 'latitude' => 1.5, 'longitude' => 2.5, 'name' => 'Casa' })
      com_legenda = location_message({ 'latitude' => 1.5, 'longitude' => 2.5, 'live' => true, 'name' => 'Casa' }, content: 'Chegando')
      equipe = instance_double(Autonomia::Agents::Operate::HistoricoDaEquipe, aplica?: true)
      allow(equipe).to receive(:historico) { |messages| messages.map { |m| { role: 'user', content: resumo.texto(m) } } }
      allow(equipe).to receive(:pergunta) { |text| text }
      allow(responder).to receive_messages(recent_messages: [sem_legenda, com_legenda], equipe: equipe)

      expect(responder.send(:history).pluck(:content)).to eq(['Localização: Casa', "Chegando\nLocalização: Casa"])
    end

    it 'leaves the contact card as in main without the flag' do
      contacts = [{ 'full_name' => 'Ana', 'phones' => ['+5511'] }]
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Ana',
                                 sender: conversation.contact, content_attributes: { 'shared_contacts' => contacts })

      expect(ai_reads(message)).to eq('Ana')
    end
  end
end
