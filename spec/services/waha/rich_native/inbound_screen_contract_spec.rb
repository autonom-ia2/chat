require 'rails_helper'
require_relative 'inbound_context'

# chat#1709: as suposições que a tela (Frontend geral, #1702) faz sobre o que o recebimento da caixa WAHA grava.
describe Waha::RichNative::Inbound do
  include_context 'with a waha inbox and its connector'

  let(:mp3) { { filename: 'musica.mp3', content_type: 'audio/mpeg', file_type: :audio } }

  def order(extra = {})
    from_connector({ waha_order: { order_id: 'O1', title: 'Pedido', text: 'Quero 2', item_count: 2, currency: 'BRL', from_me: false }
                                   .merge(extra) }, message_type: :outgoing, private: true, content: 'não suportada')
      .content_attributes['order']
  end

  describe 'with the flag' do
    before { flag_on! }

    it 'writes the order in the Cloud format with `items`, order_id as text and the total as a 2-place decimal text' do
      expect(order(total_amount: 150)).to eq('catalog_id' => nil, 'text' => 'Quero 2', 'items' => [], 'order_id' => 'O1',
                                             'item_count' => 2, 'total_amount' => '150.00', 'currency' => 'BRL', 'title' => 'Pedido')
      expect(order(total_amount: 15.99)['total_amount']).to eq('15.99')
      expect(order(total_amount: 0.5)['total_amount']).to eq('0.50')
      expect(order(total_amount: nil)['total_amount']).to be_nil
      expect(order(order_id: 123)['order_id']).to eq('123')
    end

    it 'records whether the unavailable media had a caption; without it the content is the server notice' do
      failed = { kind: 'image', caption: 'Olha', from_me: false }
      with_caption = from_connector({ waha_media_failed: failed }, message_type: :outgoing, private: true)
      without = from_connector({ waha_media_failed: { kind: 'image', from_me: false } }, message_type: :outgoing, private: true)

      expect(with_caption.content).to eq('Olha')
      expect(with_caption.content_attributes['media_unavailable']).to include('has_caption' => true)
      expect(without.content).to eq(I18n.t('waha.media_unavailable.image', locale: 'pt_BR'))
      expect(without.content_attributes['media_unavailable']).to include('has_caption' => false)
    end

    it 'marks an audio FILE (not PTT) as not a voice message' do
      audio = from_connector({ waha_media: { kind: 'audio', ptt: false } }, content: nil, attachments: [mp3])

      expect(audio.attachments.first.meta).to include('is_voice_message' => false)
      expect(audio.attachments.first.push_event_data[:meta]).to include('is_voice_message' => false)
    end

    {
      '150' => '150.00', '15.9' => '15.90', -12.5 => '-12.50', -0.001 => '0.00', 1.005 => '1.01', '1.005' => '1.01',
      'abc' => nil, Float::NAN => nil, Float::INFINITY => nil, [1] => nil
    }.each do |value, expected|
      it "formats the order total #{value.inspect} as #{expected.inspect}" do
        expect(Waha::RichNative::Inbound::Order.amount(value)).to eq(expected)
      end
    end

    it 'keeps only the digits of a shared contact wa_id' do
      message = from_connector({ waha_contacts: [{ full_name: 'Bia', phones: ['+55 11 98888-7777'], wa_id: '5511988887777:12@c.us' },
                                                 { full_name: 'Lia', phones: [], wa_id: '123456789012345@lid' },
                                                 { full_name: 'Ana', phones: [], wa_id: '5511977776666' },
                                                 { full_name: 'Sem', phones: [], wa_id: '@c.us' }] })

      # O LID não é telefone: fica nil.
      expect(message.content_attributes['shared_contacts'].pluck('wa_id')).to eq(['5511988887777', nil, '5511977776666', nil])
    end

    it 'writes shared_location.live only as exactly true' do
      live = from_connector({ waha_location: { latitude: -23.5, longitude: -46.6, live: true } })
      fixed = from_connector({ waha_location: { latitude: -23.5, longitude: -46.6, live: false } })
      text = from_connector({ waha_location: { latitude: -23.5, longitude: -46.6, live: 'true' } })

      expect(live.content_attributes['shared_location']['live']).to be(true)
      [fixed, text].each { |message| expect(message.content_attributes['shared_location']).not_to have_key('live') }
    end

    describe 'quotes' do
      let(:other_conversation) { create(:conversation, inbox: inbox, account: account, contact: conversation.contact) }

      it 'writes in_reply_to with the local id when the quoted message is in this conversation' do
        quoted = create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, inbox: inbox, account: account)

        message = from_connector({ waha_quote: { chatwoot_message_id: quoted.id, body: 'Oi' } })

        expect(message.content_attributes['in_reply_to']).to eq(quoted.id)
        expect(message.content_attributes).not_to have_key('quoted_message')
      end

      it 'writes quoted_message with the quoted content and sender_type Contact for the customer, User for the company' do
        from_customer = create(:message, message_type: :incoming, content: 'Do cliente', conversation: other_conversation, inbox: inbox,
                                         account: account, sender: conversation.contact)
        from_company = create(:message, message_type: :outgoing, content: 'Da empresa', conversation: other_conversation, inbox: inbox,
                                        account: account)

        customer_quote = from_connector({ waha_quote: { chatwoot_message_id: from_customer.id } }).content_attributes['quoted_message']
        company_quote = from_connector({ waha_quote: { chatwoot_message_id: from_company.id } }).content_attributes['quoted_message']

        expect(customer_quote).to include('message_id' => from_customer.id, 'content' => 'Do cliente', 'sender_type' => 'Contact')
        expect(company_quote).to include('message_id' => from_company.id, 'content' => 'Da empresa', 'sender_type' => 'User')
      end

      it 'writes quoted_message with the device excerpt when there is no local message' do
        message = from_connector({ waha_quote: { wa_id: 'DESCONHECIDA', body: 'Trecho citado', from_me: true } })

        expect(message.content_attributes['quoted_message']).to include('message_id' => nil, 'content' => 'Trecho citado', 'unverified' => true)
        expect(message.content_attributes).not_to have_key('in_reply_to')
      end
    end

    it 'marks the customer as the sender of the messages the connector creates for the customer' do
      message = from_connector({ waha_order: { order_id: 'O1', text: 'Quero', from_me: false } }, message_type: :outgoing, private: true)

      expect(message.sender_type).to eq('Contact')
    end
  end

  it 'leaves an audio file as main without the flag (no is_voice_message)' do
    audio = from_connector({ waha_media: { kind: 'audio', ptt: false } }, content: nil, attachments: [mp3])

    expect(audio.attachments.first.meta.to_h).not_to have_key('is_voice_message')
  end
end
