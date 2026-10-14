require 'rails_helper'

# chat#1555: o eco da Meta liga o wamid à bolha que já existe sobre o registro RELIDO sob trava (não sobre um hash lido
# antes) e, quando a mensagem estava `uncertain`, o resultado passa a `accepted`: o eco prova que saiu.
describe WhatsappHybrid::EchoReconcilerExtension do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:contact) { create(:contact, account: inbox.account, phone_number: '+5511937016094') }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
  let(:agent) { create(:user, account: inbox.account) }
  let(:attrs) { { 'whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'human' } }
  let(:message) do
    create(:message, message_type: :outgoing, content: 'Já tenho o retorno', conversation: conversation, account: inbox.account,
                     inbox: inbox, sender: agent, source_id: '3EB0AAAA', content_attributes: attrs)
  end
  let(:host_class) do
    Class.new do
      include WhatsappHybrid::EchoReconcilerExtension

      attr_reader :inbox, :messages_data

      def initialize(inbox, wamid)
        @inbox = inbox
        @messages_data = [{ id: wamid }]
      end

      public :reconcile_hybrid_echo
    end
  end

  def reconcile!(target = message)
    host_class.new(inbox, 'wamid.ECO123').reconcile_hybrid_echo(target)
  end

  it 'liga o wamid e guarda o id do WAHA' do
    reconcile!

    expect(message.reload.source_id).to eq('wamid.ECO123')
    expect(message.content_attributes).to include('whatsapp_web_id' => '3EB0AAAA', 'whatsapp_transport' => 'web')
  end

  it 'não apaga o que outro escreveu entre a leitura e a gravação (marca da mensagem rica, resultado)' do
    stale = Message.find(message.id)
    # Outro processo escreve direto na linha: o objeto `stale` não vê.
    written = attrs.merge('rich_message_sent_as' => 'text', 'whatsapp_transport_outcome' => 'accepted')
    message.update_columns(content_attributes: written) # rubocop:disable Rails/SkipsModelValidations

    reconcile!(stale)

    expect(message.reload.content_attributes).to include(
      'rich_message_sent_as' => 'text', 'whatsapp_transport_outcome' => 'accepted', 'whatsapp_web_id' => '3EB0AAAA'
    )
  end

  it 'promove uncertain para accepted quando o eco prova que a mensagem saiu' do
    message.update!(status: :failed,
                    content_attributes: attrs.merge('external_error' => 'não confirmou', 'whatsapp_transport_outcome' => 'uncertain'))

    reconcile!

    expect(message.reload.status).to eq('sent')
    expect(message.content_attributes).to include('whatsapp_transport_outcome' => 'accepted')
    expect(message.content_attributes).not_to have_key('external_error')
  end

  it 'não mexe no resultado de uma mensagem que já estava enviada' do
    message.update!(content_attributes: attrs.merge('whatsapp_transport_outcome' => 'throttled'))

    reconcile!

    expect(message.reload.content_attributes).to include('whatsapp_transport_outcome' => 'throttled')
  end
end
