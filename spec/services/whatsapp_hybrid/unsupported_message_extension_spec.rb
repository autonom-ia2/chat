require 'rails_helper'

# chat#1489: a bolha "não suportada" guarda o tipo e o código da Meta, o tipo `unknown` vira a mesma bolha e, com a
# flag e o WhatsApp API pronto, ela nasce pendente de recuperação, com o job agendado.
describe WhatsappHybrid::UnsupportedMessageExtension do
  include_context 'with a pending unsupported hybrid message'

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  let(:incoming) do
    { from: '5511937016094', id: wamid, timestamp: '1667047370', type: 'unsupported',
      errors: [{ code: 131_051, title: 'Message type unknown' }], unsupported: { type: 'hsm' } }
  end

  def deliver(item = incoming)
    params = { phone_number: channel.phone_number, object: 'whatsapp_business_account',
               entry: [{ changes: [{ value: { contacts: [{ profile: { name: 'Cliente' }, wa_id: '5511937016094' }],
                                              messages: [item] } }] }] }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
    inbox.messages.reload.last
  end

  context 'when the account has the flag and the WhatsApp API is ready' do
    it 'nasce pendente, com o id físico, e agenda a primeira tentativa em 5 s' do
      freeze_time do
        received = nil
        expect { received = deliver }.to have_enqueued_job(WhatsappHybrid::RecoverUnsupportedJob).at(5.seconds.from_now)

        expect(received.content_attributes).to include('is_unsupported' => true, 'whatsapp_web_id' => web_id,
                                                       'hybrid_recovery' => 'pending', 'unsupported_type' => 'hsm',
                                                       'unsupported_error_code' => 131_051)
      end
    end

    it 'a nossa IA não é chamada pelo message_created do aviso' do
      allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)

      event = Events::Base.new('message.created', Time.zone.now, message: deliver)

      expect { Autonomia::Agents::Operate::MessageListener.instance.message_created(event) }
        .not_to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob)
    end
  end

  context 'when the flag is off (comportamento de hoje)' do
    before { account.disable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE) }

    it 'grava o aviso com o tipo e o código, sem recuperação e sem job' do
      received = nil
      expect { received = deliver }.not_to have_enqueued_job(WhatsappHybrid::RecoverUnsupportedJob)

      expect(received.content).to eq('This message is unavailable.')
      expect(received.content_attributes).to include('is_unsupported' => true, 'unsupported_type' => 'hsm',
                                                     'unsupported_error_code' => 131_051)
      expect(received.content_attributes).not_to have_key('hybrid_recovery')
      expect(received.content_attributes).not_to have_key('whatsapp_web_id')
    end
  end

  it 'conexão desconectada: sem recuperação e sem job' do
    connection.update!(status: 'disconnected')

    expect { deliver }.not_to have_enqueued_job(WhatsappHybrid::RecoverUnsupportedJob)
    expect(inbox.messages.last.content_attributes).not_to have_key('hybrid_recovery')
  end

  it 'envio automático desligado (pausada): sem recuperação' do
    connection.update!(routing_enabled: false)

    expect { deliver }.not_to have_enqueued_job(WhatsappHybrid::RecoverUnsupportedJob)
  end

  it 'o tipo unknown vira a mesma bolha (antes a mensagem não era gravada)' do
    received = deliver(incoming.merge(type: 'unknown').except(:unsupported))

    expect(received.content).to eq('This message is unavailable.')
    expect(received.content_attributes).to include('is_unsupported' => true, 'unsupported_error_code' => 131_051,
                                                   'hybrid_recovery' => 'pending')
  end

  it 'mensagem comum não ganha nenhuma chave da recuperação' do
    received = deliver(from: '5511937016094', id: 'wamid.TEXTO', timestamp: '1667047370', type: 'text', text: { body: 'Oi' })

    expect(received.content).to eq('Oi')
    expect(received.content_attributes.keys & %w[hybrid_recovery whatsapp_web_id unsupported_type]).to be_empty
  end
end
