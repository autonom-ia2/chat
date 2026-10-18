# Prepend em Whatsapp::IncomingMessageBaseService (#1702): o que a Cloud API (e o 360dialog, e o Híbrido, que recebe
# pela Cloud) manda e o Chatwoot não tratava. Cada caso segue a doc da Meta:
# - `revoke` (cliente apagou; só coexistência): marca a ORIGINAL com `deleted_by_contact_at`; conteúdo e anexos ficam
#   (decisão do Rodrigo: o que o cliente mandou fica guardado). Não nasce balão novo.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/revoke.md
# - `edit` (cliente editou; só coexistência, "temporariamente" desligado pela Meta): troca o texto da ORIGINAL e guarda
#   o anterior em `edit_history`.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/edit.md
# - `order` (pedido do catálogo): balão de texto legível + `content_attributes.order` estruturado.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/order.md
# - `unsupported`: grava `unsupported_kind` quando a Meta diz o tipo em `unsupported.type`.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/unsupported.md
# - `context.forwarded` / `context.frequently_forwarded`: marca de encaminhada.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/text.md
# - `context.referred_product` (pergunta sobre um produto do catálogo): `referred_product` com o código e, quando o
#   catálogo responde, nome, preço e foto (ConversaCanal::ProdutoCitado).
# - status `played` (áudio ouvido): `played_at` na mensagem enviada, sem mexer no enum de status do Chatwoot.
#   https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/status.md
#
# Tudo só com a chave `conversa_cara_do_canal` da conta (ConversaCanal::Pele); desligada, o Chatwoot de sempre.
module ConversaCanal::RecebimentoDoWhatsapp
  NA_ORIGINAL = %w[revoke edit].freeze
  PEDIDO = 'order'.freeze
  NAO_SUPORTADA = 'unsupported'.freeze
  OUVIDO = 'played'.freeze
  ENCAMINHADA = %w[forwarded frequently_forwarded].freeze

  private

  # Apagada e editada mexem na mensagem que já existe: não passam pela trava de id nem criam contato ou conversa.
  # O produto citado (`context.referred_product`) é lido aqui, antes da transação que cria a mensagem: a consulta ao
  # catálogo nunca segura o banco.
  def process_messages
    return super unless pele? && messages_data.present?
    return mudar_a_original if NA_ORIGINAL.include?(message_type)

    @produto_citado = ConversaCanal::ProdutoCitado.de(messages_data.first[:context], inbox) unless outgoing_echo
    super
  end

  def mudar_a_original
    ConversaCanal::MudancaNaOriginal.new(inbox: inbox, data: messages_data.first, outgoing_echo: outgoing_echo).perform
  end

  def message_content(message)
    return super unless pele? && message[:type] == PEDIDO

    ConversaCanal::PedidoRecebido.new(message[:order], locale: account.locale).texto
  end

  def message_content_attributes(message)
    attrs = super
    return attrs unless pele?

    attrs = attrs.merge(encaminhada(message))
    attrs = attrs.merge(referred_product: @produto_citado) if @produto_citado
    attrs = attrs.merge(order: ConversaCanal::PedidoRecebido.new(message[:order]).atributos) if message[:type] == PEDIDO
    kind = message[:type] == NAO_SUPORTADA ? ConversaCanal::TipoNaoSuportado.de(message) : nil
    kind ? attrs.merge(unsupported_kind: kind) : attrs
  end

  # O pedido não tem mídia: sem isto o Chatwoot pedia à Meta o arquivo de um id que não existe.
  def attach_files
    return if pele? && message_type == PEDIDO

    super
  end

  def update_message_with_status(message, status)
    result = super
    ConversaCanal::AudioOuvido.registrar(message, status) if pele? && status[:status].to_s == OUVIDO
    result
  end

  def pele?
    ConversaCanal::Pele.ligada?(inbox.account)
  end

  def encaminhada(message)
    contexto = message[:context]
    return {} unless contexto.respond_to?(:key?)

    ENCAMINHADA.select { |chave| contexto[chave] == true }.index_with(true).symbolize_keys
  end
end
