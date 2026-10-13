# Envios ricos pelo painel (chat#1473). A mensagem é criada pela API de sempre, com o corpo em `content` e o
# formato em `content_attributes.rich_message`, que traz um `type`.
#
# COMO ACRESCENTAR UM TIPO (só arquivos novos, nenhum arquivo comum):
# 1. Crie `app/services/rich_messages/types/<type>.rb` com a classe `RichMessages::Types::<TypeEmCamelCase>`.
#    O `type` do contrato é o nome do arquivo: minúsculas, números e `_` simples (ex.: `location_request`).
# 2. A classe cumpre esta interface, e só ela (sem as três respostas o tipo não é reconhecido):
#      initialize(payload)           # o hash de `rich_message`, chaves em string
#      error_for(body)               # nil se pode sair; senão o motivo, em texto para o atendente
#      whatsapp_cloud_payload(body)  # o trecho da mensagem da Meta: `{ type: ..., <type>: {...} }`
#      fallback_text(body)           # SÓ o complemento, em texto puro; nil se o tipo não tem versão em texto
#    `body` é o texto que sai de fato (já renderizado para o canal) e pode ser vazio: quem exige corpo é o tipo.
# 3. Regras do tipo:
#    - o complemento vai sem escape nem corpo: quem junta ao corpo e escapa onde o canal é HTML é o OutgoingText;
#    - tipo sem versão em texto (`fallback_text` nil) só sai pelo WhatsApp oficial, com a janela aberta;
#    - se não der para montar o envio, levante RichMessages::DeliveryError com o motivo: a mensagem fica `failed`;
#    - nada de HTTP dentro do tipo (quem fala com a Meta é o WhatsappCloudDelivery) e nada de log com link,
#      telefone, token ou conteúdo.
# 4. Crie `spec/services/rich_messages/types/<type>_spec.rb` (payload exato da Meta, cada entrada inválida, o
#    complemento em texto). Despacho, trava, criação pela API, reenvio, texto de saída e webhook da caixa API já
#    estão cobertos com tipos de teste em `spec/services/rich_messages_spec.rb` e não mudam.
#
# Onde isto encosta no envio (tudo por prepend, em config/initializers/rich_messages.rb):
# - RichMessages::CreationCheck: a criação pela API recusa formato errado na hora (422);
# - RichMessages::SendGuard: mensagem que não pode sair fica `failed` com o motivo, em qualquer canal;
# - RichMessages::WhatsappCloudDelivery: no WhatsApp oficial sai no formato da Meta;
# - RichMessages::OutgoingText: nos outros canais o texto de saída é corpo + complemento do tipo;
# - RichMessages::ApiInboxWebhook: a caixa API recebe esse mesmo texto no webhook dela;
# - RichMessages::RetryKeepsFormat: o reenvio não apaga o formato.
module RichMessages
  KEY = 'rich_message'.freeze
  TYPE_CHARACTERS = 'a-z0-9_'.freeze
  TYPE_INTERFACE = [:error_for, :whatsapp_cloud_payload, :fallback_text].freeze
  HTML_RENDERERS = [:render_html, :render_telegram_html].freeze

  UNKNOWN_TYPE = 'Formato de mensagem desconhecido: a mensagem não foi enviada.'.freeze
  WITH_TEMPLATE = 'Mensagem com formato especial não pode ir junto com um modelo.'.freeze
  NOT_PLAIN_TEXT = 'Mensagem com formato especial precisa ser de texto simples.'.freeze
  WITH_ATTACHMENT = 'Mensagem com formato especial não pode levar anexo.'.freeze
  NO_TEXT_VERSION = 'Este formato de mensagem só pode ser enviado pelo WhatsApp oficial.'.freeze

  module_function

  # A mensagem traz a chave `rich_message`, com qualquer valor (vazio também conta: é formato inválido, não texto).
  def rich?(message)
    message.content_attributes.key?(KEY)
  end

  # O formato da mensagem, ou nil quando ela não tem `rich_message` ou o tipo não existe.
  def build(message)
    payload = message.content_attributes[KEY]
    type_class(payload['type'])&.new(payload) if payload.is_a?(Hash)
  end

  # O `type` vem de quem chama a API, então só resolve classe definida DENTRO de RichMessages::Types: nome só com
  # minúsculas, números e `_`, começando por letra (sem `::` nem `/`), que volta igual do nome da classe, e busca
  # sem herança (não alcança Object). A constante precisa ser uma classe com a interface dos tipos.
  def type_class(type)
    return unless type_name?(type) && RichMessages::Types.const_defined?(type.camelize, false)

    klass = RichMessages::Types.const_get(type.camelize, false)
    klass if klass.is_a?(Class) && (TYPE_INTERFACE - klass.public_instance_methods).empty?
  end

  def type_name?(type)
    type.is_a?(String) && type.start_with?(*('a'..'z')) && type.delete(TYPE_CHARACTERS).empty? && type.camelize.underscore == type
  end

  # Por que esta mensagem não pode sair, em texto para o atendente; nil quando pode (ou não tem `rich_message`).
  def error_for(message)
    format_error(message) || window_error(message)
  end

  # A parte que não depende do momento: combinação proibida, tipo desconhecido, entrada do tipo fora do contrato
  # e tipo sem versão em texto num canal que não é o WhatsApp oficial. É o que a criação pela API recusa na hora.
  def format_error(message)
    return unless rich?(message)

    combination_error(message) || type_error(message)
  end

  # O corpo como o canal o recebe, sem nada do formato.
  def body_text(message)
    MessageContentPresenter.new(message).outgoing_content
  end

  # Corpo + complemento do tipo, com uma linha em branco entre os dois. `html: true` escapa o complemento.
  def text_with_fallback(message, body, html: false)
    complement = build(message)&.fallback_text(body)
    return body if complement.nil?

    [body.presence, html ? CGI.escapeHTML(complement) : complement].compact.join("\n\n")
  end

  def html_channel?(inbox)
    HTML_RENDERERS.include?(Messages::MarkdownRendererService::CHANNEL_RENDERERS[inbox.channel_type])
  end

  def whatsapp_cloud?(inbox)
    inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
  end

  def combination_error(message)
    return WITH_TEMPLATE if message.additional_attributes.to_h['template_params'].present?
    return NOT_PLAIN_TEXT unless message.content_type == 'text'

    WITH_ATTACHMENT if message.attachments.present?
  end

  def type_error(message)
    rich = build(message)
    return UNKNOWN_TYPE if rich.nil?

    body = body_text(message)
    rich.error_for(body) || (NO_TEXT_VERSION if rich.fallback_text(body).nil? && !whatsapp_cloud?(message.inbox))
  end

  # Tipo sem versão em texto no WhatsApp oficial com a janela fechada: nenhum transporte de texto (WhatsApp
  # Híbrido) pode levá-lo, então falha com o erro de janela em vez de sair só o corpo.
  def window_error(message)
    return unless rich?(message) && whatsapp_cloud?(message.inbox) && build(message).fallback_text(body_text(message)).nil?
    return if Conversations::MessageWindowService.new(message.conversation).can_reply?

    I18n.t('errors.whatsapp.message_outside_messaging_window')
  end
end
