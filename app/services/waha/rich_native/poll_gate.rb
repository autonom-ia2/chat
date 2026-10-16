# Prepend na classe singleton de RichMessages, por cima de WhatsappHybrid::RichNative::DeliveryMode (chat#1709): o tipo
# `poll` (RichMessages::Types::Poll) só existe com a flag `whatsapp_rich_native` na conta.
# - format_error: flag desligada = UNKNOWN_TYPE, a mesma resposta da main para um tipo que não existe (422 na criação
#   pela API, `failed` na trava do envio).
# - delivery_mode: flag desligada = :refused (como tipo desconhecido). Com ela, no WhatsApp oficial com a janela aberta
#   a resposta original seria :native, mas a Cloud não tem enquete: sai texto (:text). O plano B do Híbrido
#   (janela fechada) continua :native, pela regra do WhatsappHybrid::RichNative::DeliveryMode.
module Waha::RichNative::PollGate
  TYPE = 'poll'.freeze

  def format_error(message)
    return RichMessages::UNKNOWN_TYPE if poll_message?(message) && !Waha::RichNative.enabled?(message.account)

    super
  end

  def delivery_mode(inbox:, type:, conversation: nil, **options)
    return :refused if type == TYPE && !Waha::RichNative.enabled?(inbox.account)

    mode = super
    return mode unless type == TYPE && mode == :native && whatsapp_cloud?(inbox)

    poll_by_hybrid?(inbox, conversation, options[:message]) ? mode : :text
  end

  def poll_message?(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && rich['type'] == TYPE
  end

  def poll_by_hybrid?(inbox, conversation, message)
    message.present? && conversation.present? &&
      WhatsappHybrid::RichNative.native_for?(inbox, TYPE, conversation, message: message)
  end
end
