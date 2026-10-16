# Prepend em Whatsapp::IncomingMessageBaseService (chat#1709): liga a resposta do cliente à lista que o WhatsApp API
# mandou nativa. A lista sai pelo aparelho, a Meta não manda eco dela e o `list_reply` que chega pela oficial vem sem
# `context` (teste na caixa 118, 16/10/2026): o Chatwoot não tem como gravar `in_reply_to`, e a bolha "O cliente tocou
# em X" (optionsAnswer.js) não acha a pergunta. O `list_reply.id` volta igual ao `rowId` enviado (no teste, "manha").
#
# Numa caixa híbrida, quando a resposta traz `selected_option` e não aponta mensagem nenhuma (`context`):
# 1. `rowId` com referência ("<opção>|<mensagem>", Waha::RichNative.split_row_id, separado pelo último "|", sem regex):
#    `selected_option.id` volta ao id ORIGINAL da opção (o robô lê o mesmo de antes). Se a mensagem existe NESTA conversa
#    e é lista nativa com essa opção, `in_reply_to` = ela (vale até com a flag desligada depois do envio: é uma consulta
#    por id). Com a flag, a referência que não confere (ex.: lista de uma conversa anterior) também sai do id.
#    Lista com id de opção que tem "|" não sai nativa (Waha::RichPayload): todo `rowId` nativo com "|" é nosso.
# 2. Sem referência, ou referência que não confere, e com a flag: `in_reply_to` = a ÚLTIMA mensagem nossa de options
#    que saiu nativa nesta conversa com uma opção de `id` IGUAL ao da opção (listas mandadas antes da referência).
# Comparação exata de id, nunca de texto. Sem nenhuma, só o `selected_option` (sem referência) muda.
module WhatsappHybrid::RichNative::ReplyLink
  # Quantas mensagens nossas, das mais novas, procurar. A lista respondida costuma ser a última.
  LOOKBACK = 50

  # { in_reply_to:, selected_option: } a gravar (só as chaves que mudam), ou nil quando nada muda.
  # `search` (a flag da conta): sem ela, só a referência que confere com uma lista nativa desta conversa (uma consulta
  # por id) liga a resposta e limpa o sufixo; nada de busca nem de limpeza sem confirmação.
  def self.link(conversation, selected, search: true)
    option_id, reference = Waha::RichNative.split_row_id(selected[:id])
    target = reference && referenced_message(conversation, reference, option_id)
    return if target.nil? && !search

    target ||= options_message_for(conversation, option_id)
    changes = {}
    changes[:in_reply_to] = target.id if target
    changes[:selected_option] = selected.merge(id: option_id) if option_id != selected[:id]
    changes.presence
  end

  def self.referenced_message(conversation, message_id, option_id)
    message = conversation.messages.find_by(id: message_id, message_type: :outgoing)
    message if message && native_options?(message) && option_ids(message).include?(option_id)
  end

  def self.options_message_for(conversation, option_id)
    return if conversation.nil? || option_id.blank?

    conversation.messages.where(message_type: :outgoing).where.not(status: :failed)
                .reorder(id: :desc).limit(LOOKBACK)
                .find { |message| native_options?(message) && option_ids(message).include?(option_id.to_s) }
  end

  # O conteúdo é JSON gravado como texto: o filtro é em Ruby, sobre poucas linhas.
  def self.native_options?(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == 'options' && Waha::RichNative.sent_native?(message)
  end

  def self.option_ids(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    options = rich['sections'].is_a?(Array) ? rich['sections'].flat_map { |section| Array(section.try(:[], 'options')) } : Array(rich['options'])
    options.filter_map { |option| option['id'].to_s if option.is_a?(Hash) && option['id'].present? }
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
