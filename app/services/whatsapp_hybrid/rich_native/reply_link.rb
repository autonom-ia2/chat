# Prepend em Whatsapp::IncomingMessageBaseService (chat#1709): liga a resposta do cliente à lista que o WhatsApp API
# mandou nativa. A lista sai pelo aparelho, a Meta não manda eco dela e o `list_reply` que chega pela oficial vem sem
# `context` (teste na caixa 118, 16/10/2026): o Chatwoot não tem como gravar `in_reply_to`, e a bolha "O cliente tocou
# em X" (optionsAnswer.js) não acha a pergunta.
# Aqui, com a flag `whatsapp_rich_native`, numa caixa híbrida, quando a resposta traz `selected_option` e nenhum
# `in_reply_to`, grava `in_reply_to` = a ÚLTIMA mensagem nossa de options que saiu nativa nesta conversa com uma opção
# de `id` IGUAL ao tocado. Comparação exata de id, nunca de texto. Sem uma assim, nada muda.
module WhatsappHybrid::RichNative::ReplyLink
  # Quantas mensagens nossas, das mais novas, procurar. A lista respondida costuma ser a última.
  LOOKBACK = 50

  def self.options_message_for(conversation, option_id)
    return if conversation.nil? || option_id.blank?

    conversation.messages.where(message_type: :outgoing).where.not(status: :failed)
                .reorder(id: :desc).limit(LOOKBACK)
                .find { |message| native_options?(message) && option_ids(message).include?(option_id.to_s) }
  end

  # O conteúdo é JSON gravado como texto: o filtro é em Ruby, sobre poucas linhas.
  def self.native_options?(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == 'options' && WhatsappHybrid::RichNative.sent_native?(message)
  end

  def self.option_ids(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    options = rich['sections'].is_a?(Array) ? rich['sections'].flat_map { |section| Array(section.try(:[], 'options')) } : Array(rich['options'])
    options.filter_map { |option| option['id'].to_s if option.is_a?(Hash) && option['id'].present? }
  end

  private

  def message_content_attributes(message)
    attributes = super
    return attributes if outgoing_echo || attributes[:in_reply_to].present? || attributes['in_reply_to'].present?

    selected = RichMessages::SelectedOption.from(message)
    return attributes if selected.nil? || !reply_link_enabled?

    target = WhatsappHybrid::RichNative::ReplyLink.options_message_for(@conversation, selected[:id])
    target ? attributes.merge(in_reply_to: target.id) : attributes
  end

  def reply_link_enabled?
    WhatsappHybrid::RichNative.enabled?(@inbox.account) && WhatsappHybrid::RichNative.hybrid?(@inbox)
  end
end
