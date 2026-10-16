# Callback `before_create` de Message (chat#1709, fase 3): os dados estruturados que o conector customizado do WAHA
# (c2y-rich-2) acrescenta à mensagem que ele cria pela API. O conector roda para TODAS as contas e mantém o texto, o tipo
# e a privacidade de antes; só junta uma destas chaves em `content_attributes`:
#   waha_poll_vote  { poll_message_id, options: [títulos], vote_id, timestamp }  + in_reply_to (a enquete)
#   waha_call       { call_id, event: received|accepted|rejected, is_video, by_me, reason }
#   waha_unknown    { content_type, from_me }
#   waha_reaction   { emoji ('' = removida), reacted_wa_id, from_me }            + in_reply_to (a reagida)
#   waha_edit       { text, edited_wa_id, from_me }                               + in_reply_to (a editada)
# Regra única:
# - flag `whatsapp_rich_native` DESLIGADA (ou caixa que não é a WAHA comum): a chave sai e nada mais muda. A mensagem
#   fica IGUAL à da main (mesmo texto, tipo e privacidade).
# - flag LIGADA na caixa WAHA comum: a mensagem vira a apresentação nova (Waha::RichNative::Inbound::<Tipo>) e a chave
#   sai. Erro em qualquer passo: a chave sai e a mensagem fica como a main (nunca interrompe a criação).
# Quem cria mensagem pela API pode mandar estas chaves (o conector também é um cliente da API): o alcance é a mesma
# conversa e caixa, como no ListReply (aceito). As chaves que o chat2you GRAVA (`c2y_hidden`, `reactions` etc.) são
# tiradas na API pelo Waha::RichNative::ForgeryGuard.
class Waha::RichNative::Inbound
  HANDLERS = {
    'waha_poll_vote' => 'Waha::RichNative::Inbound::PollVote',
    'waha_call' => 'Waha::RichNative::Inbound::Call',
    'waha_unknown' => 'Waha::RichNative::Inbound::Unknown',
    'waha_reaction' => 'Waha::RichNative::Inbound::Reaction',
    'waha_edit' => 'Waha::RichNative::Inbound::Edit'
  }.freeze
  KEYS = HANDLERS.keys.freeze

  def self.before_create(message)
    attributes = message.content_attributes.to_h
    present = KEYS.select { |key| attributes.key?(key) }
    return if present.empty?

    message.content_attributes = attributes.except(*KEYS)
    return unless transform?(message)

    key = present.first
    HANDLERS[key].constantize.apply(message, attributes[key])
  rescue StandardError => e
    Rails.logger.error("[waha] rich native inbound #{e.class}")
    message.content_attributes = message.content_attributes.to_h.except(*KEYS)
  end

  # Flag na conta e caixa WAHA comum (Channel::Api com provider 'waha').
  def self.transform?(message)
    inbox = message.inbox
    inbox&.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) && Waha::RichNative.enabled?(message.account)
  end

  # A mensagem citada pelo conector (`in_reply_to`, já resolvida pelo Chatwoot na mesma conversa), na mesma caixa.
  def self.target_of(message, **filters)
    target_id = message.content_attributes.to_h['in_reply_to']
    return if target_id.blank?

    Message.where.not(message_type: :activity)
           .find_by(id: target_id, conversation_id: message.conversation_id, inbox_id: message.inbox_id, **filters)
  end

  # A mensagem criada vira uma atividade escondida (não aparece na conversa, não vai a webhook nem à IA): fica só como
  # registro de que o evento chegou, apontando a mensagem que mudou.
  def self.hide!(message, extra = {})
    message.message_type = :activity
    message.private = false
    message.content_attributes = message.content_attributes.to_h.merge('c2y_hidden' => true).merge(extra)
  end
end
