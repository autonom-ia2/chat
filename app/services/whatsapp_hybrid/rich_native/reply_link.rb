# Prepend em Whatsapp::IncomingMessageBaseService (chat#1709): liga a resposta do cliente à lista que o WhatsApp API
# mandou nativa. A lista sai pelo aparelho, a Meta não manda eco dela e o `list_reply` que chega pela oficial vem sem
# `context` (teste na caixa 118, 16/10/2026): o Chatwoot não tem como gravar `in_reply_to`, e a bolha "O cliente tocou
# em X" (optionsAnswer.js) não acha a pergunta. O `list_reply.id` volta igual ao `rowId` enviado (no teste, "manha").
#
# Numa caixa híbrida, quando a resposta traz `selected_option` e não aponta mensagem nenhuma (`context`):
# 1. `rowId` com referência ("<opção>|<mensagem>", Waha::RichNative.split_row_id, separado pelo último "|", sem regex):
#    Se a mensagem existe NESTA conversa e é lista nativa com essa opção, `in_reply_to` = ela e `selected_option.id`
#    volta ao id ORIGINAL da opção (o robô lê o mesmo de antes), com ou sem a flag. Com a flag, a referência que não
#    confere (ex.: lista de uma conversa anterior) também sai do id; sem a flag, fica como chegou.
#    Lista com id de opção que tem "|" não sai nativa (Waha::RichPayload): todo `rowId` nativo com "|" é nosso.
# 2. Sem referência, ou referência que não confere, e com a flag: `in_reply_to` = a ÚLTIMA mensagem nossa de options
#    que saiu nativa nesta conversa com uma opção de `id` IGUAL ao da opção (listas mandadas antes da referência).
# Comparação exata de id, nunca de texto. Sem nenhuma, só o `selected_option` (sem referência) muda.
module WhatsappHybrid::RichNative::ReplyLink
  LOOKBACK = Waha::RichNative::LOOKBACK

  # { in_reply_to:, selected_option: } a gravar (só as chaves que mudam), ou nil quando nada muda.
  # `search` (a flag da conta): com ela, o sufixo `|<dígitos>` sai sempre (todo `rowId` com ele é nosso: lista com "|"
  # no id não sai nativa) e a busca pela última lista roda. Sem ela, só a referência que confere com uma lista nativa
  # nossa da conversa (uma consulta por id) liga a resposta e tira o sufixo; o resto fica como chegou.
  def self.link(conversation, selected, search: true)
    option_id, reference = Waha::RichNative.split_row_id(selected[:id])
    confirmed = reference && referenced_message(conversation, reference, option_id)
    target = confirmed || (search ? options_message_for(conversation, option_id) : nil)
    changes = {}
    changes[:in_reply_to] = target.id if target
    changes[:selected_option] = selected.merge(id: option_id) if strip_reference?(option_id, selected, confirmed, search)
    changes.presence
  end

  # O sufixo sai com a flag (todo `rowId` com ele é nosso), ou sem ela só quando a referência conferiu.
  def self.strip_reference?(option_id, selected, confirmed, search)
    option_id != selected[:id] && (confirmed.present? || search)
  end

  def self.referenced_message(conversation, message_id, option_id)
    message = conversation.messages.find_by(id: message_id, message_type: :outgoing)
    message if message && native_options?(message) && option_ids(message).include?(option_id)
  end

  def self.options_message_for(conversation, option_id)
    Waha::RichNative.latest_native_list(conversation, option_id)
  end

  def self.native_options?(message)
    Waha::RichNative.native_options?(message)
  end

  def self.option_ids(message)
    Waha::RichNative.option_ids(message)
  end

  private

  def message_content_attributes(message)
    attributes = super
    return attributes unless reply_link_candidate?(attributes)

    selected = RichMessages::SelectedOption.from(message)
    return attributes if selected.nil? || !WhatsappHybrid::RichNative.hybrid?(@inbox)

    link = WhatsappHybrid::RichNative::ReplyLink.link(@conversation, selected, search: WhatsappHybrid::RichNative.enabled?(@inbox.account))
    link ? attributes.merge(link) : attributes
  end

  # Resposta do cliente que não aponta mensagem nenhuma: sem `context` (nem um que o Chatwoot não achou) e sem
  # `in_reply_to` gravado por outro caminho.
  def reply_link_candidate?(attributes)
    !outgoing_echo && @conversation.present? && @in_reply_to_external_id.blank? &&
      attributes[:in_reply_to].blank? && attributes['in_reply_to'].blank?
  end
end
