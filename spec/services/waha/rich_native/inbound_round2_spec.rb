require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (rodada 2): o que o conector c2y-rich-3 acrescenta à mensagem que ele cria na caixa WAHA comum. Com a flag
# vira a apresentação do aparelho; sem ela, as chaves saem e a mensagem fica igual à da main.
describe Waha::RichNative::Inbound do
  include_context 'with a waha inbox and its connector'

  let(:ptt) { { filename: 'no-filename.oga', content_type: 'audio/ogg', file_type: :audio } }
  let(:webp) { { filename: 'no-filename.webp', content_type: 'image/webp', file_type: :image } }
  let(:vcard) { { filename: 'vcard-1.vcf', content_type: 'text/vcard', file_type: :file } }

  def blob_name(message)
    message.attachments.first.file.blob.filename.to_s
  end

  describe 'without the flag (main)' do
    let(:keys) do
      {
        waha_media: { kind: 'voice', ptt: true },
        waha_album: { expected_images: 3, expected_videos: 0 },
        waha_location: { latitude: -23.5, longitude: -46.6, name: 'Praça', live: false },
        waha_contacts: [{ full_name: 'Ana Souza', phones: ['+55 11 99999-0000'] }],
        waha_quote: { wa_id: 'W1', body: 'antiga', has_media: false },
        waha_media_failed: { kind: 'image', reason: 'Error' },
        waha_revoke: { revoked_wa_id: 'W1', from_me: false },
        waha_context: { forwarded: true, forwarding_score: 9, ephemeral_expiration: 86_400 },
        waha_order: { order_id: 'O1', title: 'Pedido', text: 'quero', from_me: false }
      }
    end

    it 'drops every new key and keeps text, type, privacy and attachments as main' do
      keys.each do |key, data|
        message = from_connector({ key.to_s => data }, content: 'texto de hoje', attachments: [ptt])

        expect(message).to be_incoming, key.to_s
        expect(message.content).to eq('texto de hoje'), key.to_s
        expect(message.content_attributes.keys & (described_class::KEYS + Waha::RichNative::ContractGuard::STORED_KEYS)).to eq([])
        expect(message.content_attributes.keys & %w[shared_location order]).to eq([])
        expect(message.attachments.map(&:file_type)).to eq(['audio'])
        expect(blob_name(message)).to eq('no-filename.oga')
      end
      expect(conversation.reload.messages.activity).to be_empty
    end

    it 'hides only what main never receives: the view once notice of the engine and the event reply' do
      view_once = from_connector({ waha_unknown: { content_type: 'viewOnceMessage', from_me: false } }, content: 'não suportada')
      reply = from_connector({ waha_event_response: { event_message_id: 1, response: 'going' } }, content: 'Vou')

      [view_once, reply].each { |message| expect(described_class.hidden?(message)).to be(true) }
    end
  end

  describe 'with the flag' do
    before { flag_on! }

    it 'marks a PTT as a voice message with a real name, and keeps an mp3 as plain audio' do
      mp3 = { filename: 'musica.mp3', content_type: 'audio/mpeg', file_type: :audio }
      voice = from_connector({ waha_media: { kind: 'voice', ptt: true, mimetype: 'audio/ogg; codecs=opus' } }, content: nil, attachments: [ptt])
      audio = from_connector({ waha_media: { kind: 'audio', ptt: false } }, content: nil, attachments: [mp3])

      expect(voice.attachments.first.meta).to include('is_voice_message' => true)
      expect(blob_name(voice)).to start_with('audio-').and end_with('.ogg')
      expect(voice.attachments.first.push_event_data[:meta]).to include('is_voice_message' => true)
      expect(audio.attachments.first.meta).to include('is_voice_message' => false)
      expect(blob_name(audio)).to eq('musica.mp3')
    end

    it 'turns a sticker into an image marked as sticker without text, and marks a view once media' do
      jpg = { filename: 'f.jpg', content_type: 'image/jpeg', file_type: :image }
      sticker = from_connector({ waha_media: { kind: 'sticker', animated: false } }, content: '', attachments: [webp])
      photo = from_connector({ waha_media: { kind: 'image', view_once: true } }, content: nil, attachments: [jpg])

      expect(sticker.content).to be_nil
      expect(sticker.attachments.first).to have_attributes(file_type: 'image', meta: include('is_sticker' => true))
      expect(blob_name(sticker)).to eq('sticker.webp')
      expect(photo.attachments.first.meta).to include('is_view_once' => true)
      expect(photo.attachments.first.push_event_data[:meta]).to include('is_view_once' => true)
    end

    it 'hides the album header (no empty bubble), and the AI never sees it' do
      header = from_connector({ waha_album: { expected_images: 4, expected_videos: 0 } }, content: 'Mensagem de Álbum Recebida')

      expect(described_class.hidden?(header)).to be(true)
      expect(header.content).to eq('Cabeçalho do álbum registrado (as fotos vêm em seguida)')
      expect(conversation.reload.messages.incoming).to be_empty
    end

    it 'turns a location into the map card of the official API, live included' do
      place = from_connector({ waha_location: { latitude: '-23.5505', longitude: -46.6333, name: 'Praça da Sé', address: 'Centro',
                                                url: 'https://maps.google.com/?q=1', live: false } }, content: 'Localização compartilhada')
      live = from_connector({ waha_location: { latitude: -23.5, longitude: -46.6, live: true } }, content: 'ao vivo')

      expect(place.content).to be_nil
      expect(place.content_attributes['shared_location'])
        .to eq('latitude' => -23.5505, 'longitude' => -46.6333, 'name' => 'Praça da Sé', 'address' => 'Centro')
      expect(place.attachments.sole).to have_attributes(file_type: 'location', coordinates_lat: -23.5505,
                                                        fallback_title: 'Praça da Sé, Centro', external_url: 'https://maps.google.com/?q=1')
      expect(live.content_attributes['shared_location']).to include('live' => true)
    end

    # Demo integrada: a legenda da localização ao vivo ("Estou chegando") não pode sumir.
    it 'keeps the caption of a live location in the content, next to the map card' do
      live = from_connector({ waha_location: { latitude: -23.5, longitude: -46.6, live: true, caption: ' Estou chegando ' } },
                            content: 'Localização ao vivo')

      expect(live.content).to eq('Estou chegando')
      expect(live.content_attributes['shared_location']).to include('live' => true)
      expect(live.attachments.sole.file_type).to eq('location')
    end

    it 'keeps the text when the coordinates are not valid' do
      message = from_connector({ waha_location: { latitude: 'x', longitude: 200 } }, content: 'Localização compartilhada')

      expect(message.content).to eq('Localização compartilhada')
      expect(message.attachments).to be_empty
      expect(message.content_attributes).not_to have_key('shared_location')
    end

    it 'turns one shared contact with one phone into the contact card, without the .vcf' do
      message = from_connector({ waha_contacts: [{ full_name: 'Ana Maria Souza', phones: ['+55 11 99999-0000'], wa_id: '5511999990000' }] },
                               content: 'Contato compartilhado', attachments: [vcard])

      expect(message.attachments.sole).to have_attributes(file_type: 'contact', fallback_title: '+55 11 99999-0000',
                                                          meta: { 'firstName' => 'Ana', 'lastName' => 'Maria Souza' })
      expect(message.content_attributes['shared_contacts'].sole).to include('full_name' => 'Ana Maria Souza')
      expect(message.content).to eq('Contato compartilhado')
    end

    it 'keeps the text without the .vcf when there is more than one phone' do
      message = from_connector({ waha_contacts: [{ full_name: 'Ana', phones: %w[1 2] }] }, content: 'Contatos', attachments: [vcard])

      expect(message.attachments.map(&:file_type)).to eq(%w[contact contact])
      expect(message.content).to eq('Contatos')
    end

    describe 'quotes (waha_quote)' do
      let(:older) do
        create(:conversation, inbox: inbox, account: account, contact: conversation.contact, contact_inbox: conversation.contact_inbox)
      end

      it 'links a quote of the same conversation' do
        quoted = create(:message, message_type: :outgoing, content: 'Seu pedido saiu', conversation: conversation, inbox: inbox, account: account)

        message = from_connector({ waha_quote: { wa_id: 'W1', body: 'Seu pedido saiu', chatwoot_message_id: quoted.id } })

        expect(message.content_attributes['in_reply_to']).to eq(quoted.id)
        expect(message.content_attributes).not_to have_key('quoted_message')
      end

      it 'keeps an excerpt of a quote from another conversation, or from the device when it is unknown' do
        quoted = create(:message, message_type: :outgoing, content: 'Proposta enviada', conversation: older, inbox: inbox, account: account)

        linked = from_connector({ waha_quote: { wa_id: 'W1', body: 'x', chatwoot_message_id: quoted.id } })
        unknown = from_connector({ waha_quote: { wa_id: 'W9', body: 'b' * 400, from_me: true, has_media: false } })

        expect(linked.content_attributes['quoted_message'])
          .to include('message_id' => quoted.id, 'conversation_id' => older.display_id, 'content' => 'Proposta enviada', 'sender_type' => 'User')
        expect(unknown.content_attributes['quoted_message'])
          .to eq('message_id' => nil, 'content' => 'b' * 280, 'from_me' => true, 'has_media' => false, 'unverified' => true)
      end

      it 'never links a message of another contact' do
        foreign = create(:message, message_type: :outgoing, content: 'outro', inbox: inbox, account: account,
                                   conversation: create(:conversation, inbox: inbox, account: account))

        message = from_connector({ waha_quote: { wa_id: 'W1', body: 'trecho', chatwoot_message_id: foreign.id } })

        expect(message.content_attributes['quoted_message']).to include('message_id' => nil, 'content' => 'trecho')
      end
    end

    # Forma real do conector: toda nota privada sai OUTGOING, inclusive a do cliente; quem diz a origem é o from_me.
    it 'makes a media of the customer that failed to download a visible customer message with a neutral line' do
      note = from_connector({ waha_media_failed: { kind: 'image', mimetype: 'image/jpeg', reason: 'TimeoutError', from_me: false } },
                            message_type: :outgoing, private: true, content: 'mídia sem mídia (https://waha.example/jobs/1)')

      expect(note).to be_incoming
      expect(note.private).to be(false)
      expect(note.sender).to eq(conversation.contact)
      expect(note.content).to eq('Foto não recebida (o download falhou)')
      expect(note.content_attributes['media_unavailable']).to include('kind' => 'image', 'reason' => 'download_failed')
      expect(note.processed_message_content).to eq('Foto não recebida (o download falhou)')
      expect(note.webhook_data[:processed_message_content].to_s).not_to include('jobs')
    end

    it 'keeps the note of a media or order sent by the business phone (from_me true) or of an old connector (no from_me) as main' do
      failed = { kind: 'image', mimetype: 'image/jpeg', reason: 'TimeoutError' }
      placed = { order_id: 'O1', title: 'Pedido', text: 'quero' }
      [{ from_me: true }, {}].each do |origin|
        note = from_connector({ waha_media_failed: failed.merge(origin) },
                              message_type: :outgoing, private: true, content: 'mídia sem mídia (job 1)')
        order = from_connector({ waha_order: placed.merge(origin) },
                               message_type: :outgoing, private: true, content: 'não suportada')

        [note, order].each do |message|
          expect(message).to be_outgoing
          expect(message.private).to be(true)
          expect(message.content_attributes.keys & %w[media_unavailable order]).to eq([])
        end
        expect(note.content).to eq('mídia sem mídia (job 1)')
      end
    end

    it 'marks the message deleted by the customer, keeps its content as proof and keeps the note of main' do
      original = create(:message, message_type: :incoming, content: 'Meu CPF é 1', conversation: conversation, inbox: inbox,
                                  account: account, sender: conversation.contact)

      note = from_connector({ in_reply_to: original.id, waha_revoke: { revoked_wa_id: 'W1', from_me: false } },
                            message_type: :outgoing, private: true, content: 'Esta mensagem foi excluída no WhatsApp')
      phone = from_connector({ in_reply_to: original.id, waha_revoke: { revoked_wa_id: 'W1', from_me: true } },
                             message_type: :outgoing, private: true, content: 'Esta mensagem foi excluída no WhatsApp')

      expect(described_class.hidden?(note)).to be(false)
      expect(note).to have_attributes(private: true, content: 'Esta mensagem foi excluída no WhatsApp')
      expect(note.content_attributes['revoke_applied_to']).to eq(original.id)
      original.reload
      expect(original.content).to eq('Meu CPF é 1')
      expect(original.content_attributes['deleted_by_contact_at']).to be_present
      expect(original.content_attributes).not_to have_key('deleted')
      expect(phone).to have_attributes(message_type: 'outgoing', private: true)
    end

    it 'marks forwarded messages' do
      once = from_connector({ waha_context: { forwarded: true, forwarding_score: 1 } })
      often = from_connector({ waha_context: { forwarded: true, forwarding_score: 5 } })

      expect(once.content_attributes).to include('forwarded' => true)
      expect(once.content_attributes).not_to have_key('frequently_forwarded')
      expect(often.content_attributes).to include('forwarded' => true, 'frequently_forwarded' => true)
    end

    it 'warns once per change of disappearing messages and keeps the content' do
      first = from_connector({ waha_context: { ephemeral_expiration: 86_400 } }, content: 'some depois')
      from_connector({ waha_context: { ephemeral_expiration: 86_400 } })
      from_connector({ waha_context: { ephemeral_expiration: 604_800 } })
      from_connector({ waha_context: { ephemeral_expiration: 0 } })

      notices = conversation.reload.messages.activity.order(:id)
      expect(notices.map(&:content)).to eq(['Mensagens temporárias ativadas (1 dia). O conteúdo fica guardado no chat2you.',
                                            'Mensagens temporárias ativadas (7 dias). O conteúdo fica guardado no chat2you.',
                                            'Mensagens temporárias desativadas.'])
      expect(notices.first.content_attributes['waha_ephemeral']).to include('expiration_seconds' => 86_400)
      expect(first.content).to eq('some depois')
      expect(conversation.additional_attributes['c2y_ephemeral_expiration']).to eq(0)
    end

    it 'turns an order into a customer message with order in the Cloud format' do
      message = from_connector({ waha_order: { order_id: 'O1', title: 'Pedido', text: 'Quero 2', item_count: 2, total_amount: 59.9,
                                               currency: 'BRL', from_me: false },
                                 waha_unknown: { content_type: 'orderMessage', from_me: false } },
                               message_type: :outgoing, private: true, content: 'não suportada')

      expect(message).to be_incoming
      expect(message.content).to eq('Quero 2')
      expect(message.content_attributes['order']).to include('order_id' => 'O1', 'item_count' => 2, 'total_amount' => '59.90',
                                                             'currency' => 'BRL', 'items' => [])
      expect(message.content_attributes).not_to have_key('is_unsupported')
    end

    it 'shows a view once the engine could not open as the unsupported bubble' do
      message = from_connector({ waha_unknown: { content_type: 'viewOnceMessage', from_me: false } }, content: 'não suportada')

      expect(message).to be_incoming
      expect(message.content_attributes).to include('is_unsupported' => true, 'unsupported_kind' => 'view_once')
    end

    it 'applies several keys together: forwarded sticker quoting a message' do
      quoted = create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, inbox: inbox, account: account)

      message = from_connector({ waha_media: { kind: 'sticker' }, waha_quote: { wa_id: 'W1', body: 'Oi', chatwoot_message_id: quoted.id },
                                 waha_context: { forwarded: true, forwarding_score: 1 } }, content: '', attachments: [webp])

      expect(message.attachments.first.meta).to include('is_sticker' => true)
      expect(message.content_attributes).to include('in_reply_to' => quoted.id, 'forwarded' => true)
    end

    it 'keeps the other keys when one step fails' do
      allow(Waha::RichNative::Inbound::Quote).to receive(:apply).and_raise(StandardError)

      message = from_connector({ waha_quote: { wa_id: 'W1', body: 'x' }, waha_context: { forwarded: true } })

      expect(message).to be_incoming
      expect(message.content_attributes).to include('forwarded' => true)
      expect(message.content_attributes.keys & described_class::KEYS).to eq([])
    end

    it 'drops the new keys sent by anyone other than the connector' do
      keys = { waha_context: { forwarded: true }, waha_location: { latitude: 1, longitude: 1 } }
      message = from_connector(keys, user: agent, content: 'oi')

      expect(message.content).to eq('oi')
      expect(message.content_attributes.keys & %w[forwarded shared_location waha_context waha_location]).to eq([])
    end
  end
end
