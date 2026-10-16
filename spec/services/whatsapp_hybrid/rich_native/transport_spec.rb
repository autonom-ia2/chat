require 'rails_helper'
require_relative '../rich_native_context'

# chat#1709 (fase 1): o envio pelo WhatsApp API com a flag `whatsapp_rich_native` (WhatsappHybrid::RichNative::Transport).
describe WhatsappHybrid::RichNative::Transport do
  include_context 'with a hybrid inbox for rich native'

  # Para os casos em que o envio relê o estado da sessão no motor (erro ou incerteza).
  def engine_session_up!
    allow(client).to receive(:get_session).and_return({ 'status' => 'WORKING', 'me' => { 'id' => "#{connection.connected_phone}@c.us" } })
    allow(client).to receive(:update_session)
    allow(client).to receive(:capping).and_return({ 'cappingStatus' => 'NOT_CAPPED' })
  end

  it 'sends options as text, marked as text, while the flag is off (nothing changes)' do
    message = outgoing(options)

    send_by_web(message)

    expect(client).to have_received(:send_text).once
    expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
  end

  it 'sends options as a native list with the message reference in each rowId, marks it native and keeps the engine id' do
    flag_on!
    allow(client).to receive(:send_list).and_return({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })
    message = outgoing(options)

    send_by_web(message)

    expect(client).not_to have_received(:send_text)
    expect(client).to have_received(:send_list).with(
      session: 'hybrid-test', chat_id: '5511937016094@c.us',
      message: hash_including(sections: [hash_including(rows: [{ title: 'Manhã', rowId: "manha|#{message.id}" },
                                                               { title: 'Tarde', rowId: "tarde|#{message.id}" }])])
    ).once
    message.reload
    expect(message.source_id).to eq('3EB0LIST')
    expect(message.content_attributes).to include('rich_message_sent_as' => 'native', 'whatsapp_transport_outcome' => 'accepted')
    expect(message.content_attributes).not_to have_key('rich_message_sent_text')
    expect(WhatsappHybrid::WebTransport.message_for(connection, '3EB0LIST')).to eq(message)
  end

  # Resposta real do sendList no teste de 16/10/2026: `id` com `_serialized` terminando no id físico. O source_id e o
  # Redis guardam só o id curto, como o send_text (o id gerado, `3EB0...`), que é o que o ack do webhook procura
  # (WhatsappHybrid::WebhookEventJob: `payload['id'].split('_').last`).
  it 'keeps the short physical id of the real sendList answer, the same format the text send keeps' do
    flag_on!
    serialized = 'true_5511937016094@c.us_3EB0AD0AC2E780A4D758F5'
    allow(client).to receive(:send_list).and_return({ 'id' => { 'fromMe' => true, 'remote' => '5511937016094@c.us',
                                                                'id' => '3EB0AD0AC2E780A4D758F5', '_serialized' => serialized } })
    text = create(:message, message_type: :outgoing, content: 'Oi', conversation: conversation, account: account, inbox: inbox,
                            sender: create(:user, account: account))
    send_by_web(text)
    list = outgoing(options)

    send_by_web(list)

    expect(text.reload.source_id).to eq('3EB0AAAA')
    expect(list.reload.source_id).to eq('3EB0AD0AC2E780A4D758F5')
    expect(WhatsappHybrid::WebTransport.message_for(connection, serialized.split('_').last)).to eq(list)
  end

  it 'sends a location natively with the pre-generated id in the source_id' do
    flag_on!
    allow(client).to receive(:send_location).and_return({})
    message = outgoing({ type: 'location', latitude: -23.5489, longitude: -46.6388, name: 'Unidade Centro' }, content: '')

    send_by_web(message)

    expect(client).to have_received(:send_location).with(hash_including(id: '3EB0AAAA', location: hash_including(title: 'Unidade Centro'))).once
    expect(message.reload.source_id).to eq('3EB0AAAA')
    expect(message.content_attributes['rich_message_sent_as']).to eq('native')
    expect(WhatsappHybrid::WebTransport.message_for(connection, '3EB0AAAA')).to eq(message)
  end

  it 'sends a contact card natively' do
    flag_on!
    allow(client).to receive(:send_contact_vcard).and_return(nil)
    message = outgoing({ type: 'contact', name: 'Recepção', phone: '+55 11 4000-0473' }, content: '')

    send_by_web(message)

    expect(client).to have_received(:send_contact_vcard).with(hash_including(id: '3EB0AAAA')).once
    expect(message.reload.content_attributes['rich_message_sent_as']).to eq('native')
  end

  it 'keeps a link button as text even with the flag on' do
    flag_on!
    message = outgoing({ type: 'link_button', label: 'Abrir', url: 'https://exemplo.com.br/x' })

    send_by_web(message)

    expect(client).to have_received(:send_text).once
    expect(message.reload.content_attributes['rich_message_sent_as']).to eq('text')
  end

  it 'sends text when the options do not fit the WhatsApp list (button or a body that cannot be the title)' do
    flag_on!
    long_button = outgoing({ type: 'options', button: 'Um botão comprido demais', options: [{ id: 'a', title: 'A' }] })
    multiline_body = outgoing(options, content: "Qual horário?\nResponda abaixo")

    send_by_web(long_button)
    send_by_web(multiline_body)

    expect(client).to have_received(:send_text).twice
    expect([long_button, multiline_body].map { |message| message.reload.content_attributes['rich_message_sent_as'] }).to eq(%w[text text])
  end

  { 'a 400' => 400, 'a 422' => 422, 'the 501 of a format the engine does not have' => 501 }.each do |title, status|
    it "sends the text ONCE when the engine refuses the native send with #{title} (nothing went out)" do
      flag_on!
      allow(client).to receive(:send_list).and_raise(Waha::Client::Error.new("WAHA POST /api/sendList -> #{status}: no", status: status))
      message = outgoing(options)

      send_by_web(message)

      expect(client).to have_received(:send_list).once
      expect(client).to have_received(:send_text).with(hash_including(id: '3EB0AAAA')).once
      expect(message.reload.source_id).to eq('3EB0AAAA')
      expect(message.status).not_to eq('failed')
      expect(message.content_attributes).to include('rich_message_sent_as' => 'text', 'whatsapp_transport_outcome' => 'accepted')
    end
  end

  it 'leaves a 5xx of the native send uncertain, without the text on top' do
    flag_on!
    engine_session_up!
    allow(client).to receive(:send_list).and_raise(Waha::Client::Error.new('WAHA POST /api/sendList -> 500: boom', status: 500))
    message = outgoing(options)

    send_by_web(message)

    expect(client).not_to have_received(:send_text)
    expect(message.reload.content_attributes['whatsapp_transport_outcome']).to eq('uncertain')
    expect(message.content_attributes['external_error']).to eq(WhatsappHybrid::WebTransport::UNCONFIRMED_ERROR)
  end

  # Limitação aceita (#1709): a lista não leva id antes do envio. Sem resposta, fica incerta com o aviso de conferir no
  # celular (a Meta não ecoa lista: não há eco que a confirme nem duplique).
  it 'leaves a native send without answer uncertain, without the text on top' do
    flag_on!
    allow(client).to receive(:send_list).and_raise(Waha::Client::Timeout, 'WAHA POST /api/sendList sem resposta')
    message = outgoing(options)

    send_by_web(message)

    expect(client).not_to have_received(:send_text)
    expect(message.reload.source_id).to eq("waha-native-pending-#{message.id}")
    expect(message.content_attributes['whatsapp_transport_outcome']).to eq('uncertain')
    expect(message.content_attributes['external_error']).to eq(WhatsappHybrid::WebTransport::UNCONFIRMED_ERROR)
  end

  it 'never falls back to text on the WhatsApp refusals the send already handles (463)' do
    flag_on!
    engine_session_up!
    allow(client).to receive(:send_list).and_raise(Waha::Client::Error.new('WAHA POST /api/sendList -> 400: error 463', status: 400))
    allow(WhatsappHybrid::TimelockRefreshJob).to receive(:perform_later)
    message = outgoing(options)

    send_by_web(message)

    expect(client).not_to have_received(:send_text)
    expect(message.reload.status).to eq('failed')
  end

  it 'keeps the provisional source_id and logs the response class and the message id when the list answer has no id' do
    flag_on!
    allow(client).to receive(:send_list).and_return({ 'status' => 'ok' })
    allow(Rails.logger).to receive(:warn)
    message = outgoing(options)

    send_by_web(message)

    expect(Rails.logger).to have_received(:warn)
      .with("[whatsapp_hybrid] rich native without id in response message=#{message.id} response=Hash")
    expect(message.reload.source_id).to eq("waha-native-pending-#{message.id}")
    expect(message.content_attributes).to include('rich_message_sent_as' => 'native', 'whatsapp_transport_outcome' => 'accepted')
  end

  it 'writes the provisional source_id before calling the engine, and swaps it for the physical id after' do
    flag_on!
    message = outgoing(options)
    seen = nil
    allow(client).to receive(:send_list) do
      seen = message.reload.source_id
      { 'id' => 'true_5511937016094@c.us_3EB0LIST' }
    end

    send_by_web(message)

    expect(seen).to eq("waha-native-pending-#{message.id}")
    expect(message.reload.source_id).to eq('3EB0LIST')
    expect(Redis::Alfred.get(WhatsappHybrid::WebTransport.message_key(connection, "waha-native-pending-#{message.id}"))).to be_nil
  end

  # A lista não leva id ao motor: um `source_id` provisório é gravado ANTES do pedido. Com `source_id`, o
  # Base::SendOnChannelService ignora a mensagem, e um novo SendReplyJob não reenvia a lista.
  it 'does not send the list again when something breaks right after sendList and the SendReplyJob runs again' do
    flag_on!
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(client).to receive(:send_list).and_return({ 'id' => 'true_5511937016094@c.us_3EB0LIST' })
    allow(WhatsappHybrid::RichNative).to receive(:mark_sent!).and_raise(ActiveRecord::ConnectionFailed)
    message = outgoing(options)

    expect { SendReplyJob.perform_now(message.id) }.to raise_error(ActiveRecord::ConnectionFailed)
    expect(message.reload.source_id).to eq("waha-native-pending-#{message.id}")
    SendReplyJob.perform_now(message.id)

    expect(client).to have_received(:send_list).once
    expect(client).not_to have_received(:send_text)
  end

  describe 'the native mark (Waha::RichNative.mark_sent!)' do
    # A validação de rajada do Chatwoot (`prevent_message_flooding`) de verdade: a conversa já passou do limite por minuto.
    it 'is written even when the conversation is over the message flooding limit, which update! would refuse' do
      message = outgoing(options)
      allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(1)
      expect { message.update!(content: 'x') }.to raise_error(ActiveRecord::RecordInvalid, /Too many messages/)
      message.reload

      expect(Waha::RichNative.mark_sent!(message, '3EB0MARK')).to be(true)

      expect(message.reload.source_id).to eq('3EB0MARK')
      expect(message.content_attributes['rich_message_sent_as']).to eq('native')
    end

    it 'logs and reports to the tracker when the write breaks, without raising' do
      message = outgoing(options)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)
      allow(message).to receive(:save!).and_raise(ActiveRecord::Deadlocked)
      allow(Rails.logger).to receive(:error)

      expect(Waha::RichNative.mark_sent!(message, '3EB0MARK')).to be(false)

      expect(Rails.logger).to have_received(:error).with("[waha] rich native mark failed message=#{message.id} ActiveRecord::Deadlocked")
      expect(tracker).to have_received(:capture_exception)
    end
  end
end
