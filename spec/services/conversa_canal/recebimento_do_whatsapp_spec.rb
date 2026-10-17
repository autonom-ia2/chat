require 'rails_helper'

# #1702: recebimento do WhatsApp oficial "igual ao app". Payloads conforme a doc da Meta (links no módulo).
#
# Comportamento ANTES deste prepend (lido no código, Whatsapp::IncomingMessageBaseService):
# - `revoke`, `edit` e `order` não estão em `unprocessable_message_type?` nem em `create_messages`: caem em
#   `create_regular_message` -> `attach_files`, que pega `messages[0][type]` como se fosse mídia e pede à Meta o arquivo
#   de um id inexistente (`media_url(nil)`). Em teste o WebMock barra o pedido (o job levanta); em produção a Graph
#   recusa, `download_attachment_file` devolve nil e nasce um balão VAZIO com o id do evento. A original fica igual.
# - `unsupported`: aviso genérico sem o tipo (`unsupported.type` é descartado).
# - `context.forwarded` / `frequently_forwarded`: descartados.
# - status `played`: Messages::StatusUpdateService recusa (fora do enum) e nada é gravado.
# Os exemplos abaixo provam que nenhum desses efeitos acontece mais: sem pedido de mídia (WebMock levantaria), sem
# balão novo para apagada/editada, com as marcas novas.
describe ConversaCanal::RecebimentoDoWhatsapp do
  before { inbox.account.enable_features!('conversa_cara_do_canal') }

  after { Redis::Alfred.scan_each(match: 'MESSAGE_SOURCE_KEY::*') { |key| Redis::Alfred.delete(key) } }

  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { channel.inbox }
  let(:wa_id) { '5511937016094' }
  let(:contact) { create(:contact, account: inbox.account, phone_number: "+#{wa_id}") }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, contact: contact, source_id: wa_id) }
  let(:conversation) { create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox, account: inbox.account) }
  let(:original) do
    create(:message, message_type: :incoming, content: 'Meu CPF é 123', conversation: conversation, account: inbox.account,
                     inbox: inbox, sender: contact, source_id: 'wamid.ORIGINAL')
  end

  def cloud_params(value)
    { phone_number: channel.phone_number, object: 'whatsapp_business_account',
      entry: [{ changes: [{ field: 'messages', value: value }] }] }.with_indifferent_access
  end

  def receive(message, outgoing_echo: false)
    value = if outgoing_echo
              { message_echoes: [message.merge(from: channel.phone_number.delete('+'), to: wa_id)] }
            else
              { contacts: [{ profile: { name: 'Cliente' }, wa_id: wa_id }], messages: [message.merge(from: wa_id)] }
            end
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: cloud_params(value), outgoing_echo: outgoing_echo).perform
  end

  def evento(type, payload, id: "wamid.#{type.upcase}", timestamp: '1792141200')
    { 'id' => id, 'timestamp' => timestamp, 'type' => type, type => payload }
  end

  describe 'mensagem apagada pelo cliente (revoke)' do
    let(:apagou) { evento('revoke', { original_message_id: 'wamid.ORIGINAL' }) }

    it 'marca a original com deleted_by_contact_at e guarda o conteúdo, sem balão novo' do
      original

      expect { receive(apagou) }.not_to change(Message, :count)
      original.reload
      expect(original.content_attributes['deleted_by_contact_at']).to eq(Time.zone.at(1_792_141_200).iso8601)
      expect(original.content).to eq('Meu CPF é 123')
      expect(original.content_attributes['deleted']).to be_nil
    end

    it 'não apaga os anexos da original' do
      original.attachments.create!(account_id: inbox.account_id, file_type: :location, coordinates_lat: -23.5,
                                   coordinates_long: -46.6, fallback_title: 'Loja')

      receive(apagou)

      expect(original.reload.attachments.count).to eq(1)
    end

    it 'mantém a primeira hora quando o aviso chega de novo' do
      original
      receive(apagou)
      receive(evento('revoke', { original_message_id: 'wamid.ORIGINAL' }, id: 'wamid.REVOKE2', timestamp: '1792141999'))

      expect(original.reload.content_attributes['deleted_by_contact_at']).to eq(Time.zone.at(1_792_141_200).iso8601)
    end

    it 'ignora quando a original não está aqui' do
      conversation

      expect { receive(evento('revoke', { original_message_id: 'wamid.SUMIU' })) }.not_to change(Message, :count)
    end

    it 'ignora mensagem que não veio do cliente' do
      original.update!(message_type: :outgoing, sender: nil)

      receive(apagou)

      expect(original.reload.content_attributes).not_to have_key('deleted_by_contact_at')
    end

    it 'ignora o eco (apagada pelo próprio número)' do
      original

      expect { receive(apagou, outgoing_echo: true) }.not_to change(Message, :count)
      expect(original.reload.content_attributes).not_to have_key('deleted_by_contact_at')
    end
  end

  describe 'mensagem editada pelo cliente (edit)' do
    def editou(texto, id: 'wamid.EDIT', timestamp: '1792141300')
      evento('edit', { original_message_id: 'wamid.ORIGINAL', message: { type: 'text', text: { body: texto } } },
             id: id, timestamp: timestamp)
    end

    it 'troca o texto da original e guarda o anterior no histórico, sem balão novo' do
      original

      expect { receive(editou('Meu CPF é 456')) }.not_to change(Message, :count)
      original.reload
      quando = Time.zone.at(1_792_141_300).iso8601
      expect(original.content).to eq('Meu CPF é 456')
      expect(original.content_attributes['edited_at']).to eq(quando)
      expect(original.content_attributes['edit_history']).to eq(
        [{ 'content' => 'Meu CPF é 123', 'edited_at' => quando, 'sender_type' => 'Contact', 'sender_id' => contact.id }]
      )
    end

    it 'empilha as edições da mais antiga para a mais nova' do
      original
      receive(editou('segunda'))
      receive(editou('terceira', id: 'wamid.EDIT2', timestamp: '1792141400'))

      expect(original.reload.content).to eq('terceira')
      expect(original.content_attributes['edit_history'].pluck('content')).to eq(['Meu CPF é 123', 'segunda'])
    end

    it 'usa a legenda quando a edição é de mídia' do
      original
      receive(evento('edit', { original_message_id: 'wamid.ORIGINAL',
                               message: { type: 'image', image: { caption: 'Legenda nova', id: '123', mime_type: 'image/jpeg' } } }))

      expect(original.reload.content).to eq('Legenda nova')
    end

    # Revisão de segurança: aviso fora do formato não derruba o webhook (a Meta reentregaria para sempre).
    it 'aviso fora do formato (bloco em texto, hora em lista) não levanta nem mexe na original' do
      original

      [evento('edit', 'texto solto'), evento('revoke', 'texto solto'),
       evento('edit', { original_message_id: 'wamid.ORIGINAL', message: { type: 'text', text: 'solto' } }),
       evento('edit', { original_message_id: 'wamid.ORIGINAL', message: { type: 'text', text: { body: 'x' } } }, timestamp: [1])]
        .each_with_index { |aviso, i| expect { receive(aviso.merge('id' => "wamid.MAL#{i}")) }.not_to raise_error }

      expect(original.reload.content).to eq('x')
    end

    it 'não muda nada quando a edição chega de novo com o mesmo texto' do
      original
      receive(editou('Meu CPF é 456'))
      receive(editou('Meu CPF é 456', id: 'wamid.EDIT-REPETIDA'))

      expect(original.reload.content_attributes['edit_history'].size).to eq(1)
    end
  end

  describe 'pedido do catálogo (order)' do
    let(:pedido) do
      evento('order', { catalog_id: '194836987003835', text: 'Quero estes',
                        product_items: [
                          { product_retailer_id: 'camisa-p', quantity: 2, item_price: 50, currency: 'BRL' },
                          { product_retailer_id: 'bone', quantity: 1, item_price: 1050.5, currency: 'BRL' }
                        ] })
    end

    before { inbox.account.update!(locale: 'pt_BR') }

    it 'grava o pedido estruturado e um resumo legível, sem pedir mídia à Meta' do
      receive(pedido)
      message = Message.find_by!(source_id: 'wamid.ORDER')

      expect(message.content).to eq("🛒 Pedido do catálogo: 3 itens · total BRL 1.150,50\n• camisa-p × 2\n• bone × 1\nQuero estes")
      expect(message.content_attributes['order']).to eq(
        'catalog_id' => '194836987003835', 'text' => 'Quero estes',
        'items' => [
          { 'product_retailer_id' => 'camisa-p', 'quantity' => 2, 'item_price' => 50, 'currency' => 'BRL' },
          { 'product_retailer_id' => 'bone', 'quantity' => 1, 'item_price' => 1050.5, 'currency' => 'BRL' }
        ]
      )
      expect(message.attachments).to be_empty
    end

    it 'sai sem total quando os itens têm moedas diferentes' do
      itens = [
        { product_retailer_id: 'a', quantity: 1, item_price: 10, currency: 'BRL' },
        { product_retailer_id: 'b', quantity: 1, item_price: 10, currency: 'USD' }
      ]
      receive(evento('order', { catalog_id: '1', product_items: itens }))

      expect(Message.find_by!(source_id: 'wamid.ORDER').content).to eq("🛒 Pedido do catálogo: 2 itens\n• a × 1\n• b × 1")
    end

    it 'pedido fora do formato entra só com o resumo, sem derrubar o recebimento' do
      receive(evento('order', { catalog_id: '1', product_items: { a: 'b' } }, id: 'wamid.ORDER1'))
      item_quebrado = { product_retailer_id: 'a', quantity: [2], item_price: 10, currency: 'BRL' }
      receive(evento('order', { catalog_id: '1', product_items: [item_quebrado, 'texto'] }, id: 'wamid.ORDER2'))

      expect(Message.find_by!(source_id: 'wamid.ORDER1').content).to start_with('🛒 Pedido do catálogo:')
      expect(Message.find_by!(source_id: 'wamid.ORDER1').content).not_to include('total')
      expect(Message.find_by!(source_id: 'wamid.ORDER2').content_attributes.dig('order', 'items').size).to eq(1)
    end
  end

  describe 'não suportada com o tipo dito pela Meta' do
    def nao_suportada(tipo)
      erros = [{ code: 131_051, title: 'Message type unknown', message: 'Message type unknown',
                 error_data: { details: 'Message type is currently not supported.' } }]
      { id: "wamid.UNSUP-#{tipo}", timestamp: '1792141200', type: 'unsupported', errors: erros,
        unsupported: tipo ? { type: tipo } : nil }.compact
    end

    {
      'poll_creation' => 'poll', 'poll_update' => 'poll', 'gif' => 'gif', 'pin' => 'pinned', 'edit' => 'edit',
      'group_invite' => 'unknown'
    }.each do |tipo_da_meta, esperado|
      it "grava unsupported_kind=#{esperado} para unsupported.type=#{tipo_da_meta}" do
        receive(nao_suportada(tipo_da_meta))
        attrs = Message.find_by!(source_id: "wamid.UNSUP-#{tipo_da_meta}").content_attributes

        expect(attrs['unsupported_kind']).to eq(esperado)
        expect(attrs['is_unsupported']).to be(true)
      end
    end

    it 'unsupported em texto (fora do formato) não levanta e não chuta o tipo' do
      receive(nao_suportada(nil).merge(id: 'wamid.UNSUP-TEXTO', unsupported: 'poll'))

      expect(Message.find_by!(source_id: 'wamid.UNSUP-TEXTO').content_attributes).not_to have_key('unsupported_kind')
    end

    it 'não chuta o tipo quando a Meta não diz (ex.: 131060)' do
      receive({ id: 'wamid.UNSUP-SEM', timestamp: '1792141200', type: 'unsupported',
                errors: [{ code: 131_060, title: 'This message is currently unavailable.' }] })
      attrs = Message.find_by!(source_id: 'wamid.UNSUP-SEM').content_attributes

      expect(attrs).not_to have_key('unsupported_kind')
      expect(attrs['is_unsupported']).to be(true)
    end
  end

  describe 'encaminhada' do
    def texto(id, context = nil)
      { id: id, timestamp: '1792141200', type: 'text', text: { body: 'oi' }, context: context }.compact
    end

    it 'grava forwarded' do
      receive(texto('wamid.FWD', { forwarded: true }))
      attrs = Message.find_by!(source_id: 'wamid.FWD').content_attributes

      expect(attrs['forwarded']).to be(true)
      expect(attrs).not_to have_key('frequently_forwarded')
    end

    it 'grava frequently_forwarded' do
      receive(texto('wamid.FFWD', { frequently_forwarded: true }))

      expect(Message.find_by!(source_id: 'wamid.FFWD').content_attributes['frequently_forwarded']).to be(true)
    end

    it 'com a chave desligada, sai sem as marcas (Chatwoot de sempre)' do
      inbox.account.disable_features!('conversa_cara_do_canal')
      receive(texto('wamid.FWD-OFF', { forwarded: true }))

      expect(Message.find_by!(source_id: 'wamid.FWD-OFF').content_attributes).not_to have_key('forwarded')
    end

    it 'texto comum sai sem as marcas' do
      receive(texto('wamid.TXT'))
      attrs = Message.find_by!(source_id: 'wamid.TXT').content_attributes

      expect(attrs.keys).not_to include('forwarded', 'frequently_forwarded')
    end
  end

  describe 'áudio ouvido (status played)' do
    let!(:audio) do
      create(:message, message_type: :outgoing, content: nil, conversation: conversation, account: inbox.account,
                       inbox: inbox, source_id: 'wamid.AUDIO', status: :read)
    end

    def status(estado, timestamp: '1792141500', id: 'wamid.AUDIO')
      Whatsapp::IncomingMessageWhatsappCloudService.new(
        inbox: inbox, params: cloud_params(statuses: [{ id: id, status: estado, timestamp: timestamp, recipient_id: wa_id }])
      ).perform
    end

    it 'grava played_at e mantém o status do Chatwoot' do
      status('played')

      audio.reload
      expect(audio.content_attributes['played_at']).to eq(Time.zone.at(1_792_141_500).iso8601)
      expect(audio.status).to eq('read')
    end

    it 'com a chave desligada, não grava played_at' do
      inbox.account.disable_features!('conversa_cara_do_canal')
      status('played')

      expect(audio.reload.content_attributes).not_to have_key('played_at')
    end

    it 'guarda só a primeira vez' do
      status('played')
      status('played', timestamp: '1792149999')

      expect(audio.reload.content_attributes['played_at']).to eq(Time.zone.at(1_792_141_500).iso8601)
    end

    it 'ignora played em mensagem recebida' do
      original
      status('played', id: 'wamid.ORIGINAL')

      expect(original.reload.content_attributes).not_to have_key('played_at')
    end

    it 'os outros status seguem como antes' do
      status('failed')

      expect(audio.reload.status).to eq('failed')
      expect(audio.content_attributes).not_to have_key('played_at')
    end
  end
end
