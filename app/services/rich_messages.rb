# Envios ricos pelo painel (chat#1473). A mensagem é criada pela API de sempre, com o corpo em `content` e o
# formato em `content_attributes.rich_message`, que traz um `type`.
#
# COMO ACRESCENTAR UM TIPO (só arquivos novos, nenhum arquivo comum):
# 1. Crie `app/services/rich_messages/types/<type>.rb` com a classe `RichMessages::Types::<TypeEmCamelCase>`.
#    O `type` do contrato é o nome do arquivo: minúsculas, números e `_` (ex.: `location_request`).
# 2. A classe cumpre esta interface, e só ela:
#      initialize(payload)           # o hash de `rich_message`, chaves em string
#      error_for(body)               # nil se pode sair; senão o motivo, em texto para o atendente
#      whatsapp_cloud_payload(body)  # o trecho da mensagem da Meta: `{ type: ..., <type>: {...} }`
#      fallback_text(body)           # o texto para o canal que não tem o formato
# 3. Crie `spec/services/rich_messages/types/<type>_spec.rb` (payload exato da Meta, cada entrada inválida,
#    texto de reserva). O despacho, a trava, o reenvio e o texto de saída já estão cobertos em
#    `spec/services/rich_messages_spec.rb` e não mudam.
#
# Onde isto encosta no envio (tudo por prepend, em config/initializers/rich_messages.rb):
# - RichMessages::SendGuard: mensagem com `rich_message` inválido falha com erro legível, em qualquer canal;
# - RichMessages::WhatsappCloudDelivery: no WhatsApp oficial sai no formato da Meta;
# - RichMessages::OutgoingText: nos outros canais o texto de saída é o texto de reserva do tipo;
# - RichMessages::RetryKeepsFormat: o reenvio não apaga o formato.
module RichMessages
  KEY = 'rich_message'.freeze
  TYPE_CHARACTERS = 'a-z0-9_'.freeze
  UNKNOWN_TYPE = 'Formato de mensagem desconhecido: a mensagem não foi enviada.'.freeze

  module_function

  # O formato da mensagem, ou nil quando ela não tem `rich_message` ou o tipo não existe.
  def build(message)
    payload = message.content_attributes[KEY]
    type_class(payload['type'])&.new(payload) if payload.is_a?(Hash)
  end

  # O `type` vem de quem chama a API, então só resolve classe definida DENTRO de RichMessages::Types: nome só com
  # minúsculas, números e `_`, começando por letra (sem `::` nem `/`), e busca sem herança (não alcança Object).
  def type_class(type)
    return unless type.is_a?(String) && type.start_with?(*('a'..'z')) && type.delete(TYPE_CHARACTERS).empty?

    name = type.camelize
    RichMessages::Types.const_get(name, false) if RichMessages::Types.const_defined?(name, false)
  end

  # Por que esta mensagem não pode sair, em texto para o atendente; nil quando pode (ou não tem `rich_message`).
  def error_for(message)
    return if message.content_attributes[KEY].nil?

    rich = build(message)
    rich ? rich.error_for(message.content) : UNKNOWN_TYPE
  end

  # O corpo como o canal o recebe, sem nada do formato.
  def body_text(message)
    MessageContentPresenter.new(message).outgoing_content
  end

  # O texto de reserva: o que enviar por um transporte que não tem o formato (no botão de link, corpo + link).
  # Sem `rich_message` é o texto de saída de sempre.
  def fallback_text(message)
    message.outgoing_content
  end
end
