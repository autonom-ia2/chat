# Prepend na classe singleton de RichMessages, por cima de WhatsappHybrid::RichNative::DeliveryMode (chat#1709): os tipos
# `poll` (RichMessages::Types::Poll) e `event` (RichMessages::Types::Event, rodada 2) só existem com a flag
# `whatsapp_rich_native` na conta.
# - format_error: flag desligada = UNKNOWN_TYPE, a mesma resposta da main para um tipo que não existe (422 na criação
#   pela API, `failed` na trava do envio).
# - delivery_mode: flag desligada = :refused (como tipo desconhecido). Com ela, no WhatsApp oficial com a janela aberta
#   a resposta original seria :native, mas a Cloud não tem enquete nem convite de evento: sai texto (:text). O plano B
#   do Híbrido (janela fechada) continua :native, pela regra do WhatsappHybrid::RichNative::DeliveryMode.
# - build: o convite de evento recebe o fuso da conta, para a data da versão em texto.
module Waha::RichNative::PollGate
  TYPE = 'poll'.freeze
  FLAG_TYPES = %w[poll event].freeze

  def format_error(message)
    return RichMessages::UNKNOWN_TYPE if flag_type_message?(message) && !Waha::RichNative.enabled?(message.account)

    super
  end

  def delivery_mode(inbox:, type:, conversation: nil, **options)
    return :refused if FLAG_TYPES.include?(type) && !Waha::RichNative.enabled?(inbox.account)

    mode = super
    return mode unless FLAG_TYPES.include?(type) && mode == :native && whatsapp_cloud?(inbox)

    native_by_hybrid?(inbox, type, conversation, options[:message]) ? mode : :text
  end

  # O convite de evento escreve a data da versão em texto no fuso da conta.
  def build(message)
    return super unless type_class_of(message) == RichMessages::Types::Event

    zone = Crm::Timezone::Resolver.new(account: message.account).zone_or_default
    RichMessages::Types::Event.new(message.content_attributes[RichMessages::KEY], zone: zone)
  end

  def flag_type_message?(message)
    rich = message.content_attributes.to_h[RichMessages::KEY]
    rich.is_a?(Hash) && FLAG_TYPES.include?(rich['type'])
  end

  def native_by_hybrid?(inbox, type, conversation, message)
    message.present? && conversation.present? &&
      WhatsappHybrid::RichNative.native_for?(inbox, type, conversation, message: message)
  end
end
