# Envios ricos pelo painel (chat#1473). A mensagem é criada pela API de sempre, com o corpo em `content` e o
# formato em `content_attributes.rich_message`, que traz um `type`.
#
# COMO ACRESCENTAR UM TIPO (só arquivos novos, nenhum arquivo comum):
# 1. Crie `app/services/rich_messages/types/<type>.rb` com a classe `RichMessages::Types::<TypeEmCamelCase>`.
#    O `type` do contrato é o nome do arquivo e precisa voltar igual do nome da classe: minúsculas e números,
#    com `_` só entre palavras que começam por letra. `location_request` serve (LocationRequest); `step_1` não
#    (Step1 volta `step1`): escreva `step1` ou `first_step`.
# 2. A classe cumpre esta interface (sem as três respostas de instância o tipo não é reconhecido):
#      initialize(payload)           # o hash de `rich_message`, chaves em string
#      error_for(body)               # nil se pode sair; senão o motivo, em texto para o atendente
#      whatsapp_cloud_payload(body)  # o trecho da mensagem da Meta: `{ type: ..., <type>: {...} }`
#      fallback_text(body)           # a versão em texto do formato, sem o corpo
#      self.text_version?            # OPCIONAL, de classe; padrão true. Só quem NÃO tem versão em texto declara
#                                    # `def self.text_version? = false`
#    `body` é o texto que sai de fato (já renderizado para o canal) e pode ser vazio: quem exige corpo é o tipo.
# 3. Versão em texto:
#    - tipo com `self.text_version? = false` só sai pelo WhatsApp oficial, com a janela aberta; nos outros canais
#      (e no plano B do Híbrido) é recusado, e o `fallback_text` dele nunca é usado;
#    - `fallback_text` em branco (""): a versão em texto é só o corpo;
#    - `fallback_text` com texto: sai o corpo, uma linha em branco e esse complemento. Vai em texto puro, sem
#      escape e sem o corpo: quem junta e escapa onde o canal é HTML é o OutgoingText.
#    Quem decide se o tipo sai por um canal é só o `self.text_version?`: a trava, o roteador do Híbrido e o
#    RichMessages.delivery_mode (que o agente consulta antes de montar a mensagem) leem essa mesma resposta.
# 4. Regras do tipo:
#    - corpo e formato saem numa mensagem só. Tipo cujo formato na Meta não tem corpo (`location`, `contact`)
#      recusa corpo não vazio no `error_for`, em vez de mandar duas mensagens ou perder o corpo;
#    - se não der para montar o envio, levante RichMessages::DeliveryError com o motivo: a mensagem fica `failed`;
#    - nada de HTTP dentro do tipo (quem fala com a Meta é o WhatsappCloudDelivery) e nada de log com link,
#      telefone, token ou conteúdo (`rich_message` já sai filtrado do log de parâmetros);
#    - as mensagens de erro são constantes dentro do arquivo do tipo;
#    - quem precisar de prepend novo (recebimento, redação de dados) cria um initializer PRÓPRIO; não edite
#      `config/initializers/rich_messages.rb`.
# 5. Crie `spec/services/rich_messages/types/<type>_spec.rb` (payload exato da Meta, cada entrada inválida, a
#    versão em texto) e o documento da entrega em `docs/audit/`, sem editar o do botão de link. Despacho, trava,
#    criação pela API, reenvio, texto de saída, webhook da caixa API e plano B do Híbrido já estão cobertos com
#    tipos de teste em `spec/services/rich_messages_spec.rb` e vizinhos, e não mudam.
#
# "WhatsApp oficial" aqui é só a caixa `Channel::Whatsapp` com `provider: 'whatsapp_cloud'`. A do 360dialog
# (`provider: 'default'`) recebe a versão em texto, como os outros canais.
#
# Onde isto encosta no envio (tudo por prepend, em config/initializers/rich_messages.rb):
# - RichMessages::CreationCheck: a criação pela API recusa formato errado na hora (422);
# - RichMessages::SendGuard: mensagem que não pode sair fica `failed` com o motivo, em qualquer canal;
# - RichMessages::WhatsappCloudDelivery: no WhatsApp oficial sai no formato da Meta;
# - RichMessages::OutgoingText: nos outros canais o texto de saída é corpo + versão em texto do tipo;
# - RichMessages::ApiInboxWebhook: a caixa API recebe esse mesmo texto no webhook dela;
# - RichMessages::RetryKeepsFormat: o reenvio não apaga o formato.
# E o WhatsappHybrid::Router consulta RichMessages.text_capable? antes de mandar a mensagem em texto.
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
  # Canais em que nem o formato nem a versão em texto chegam: o e-mail monta o corpo por campos próprios, sem ler
  # o texto de saída, e o chat do site mostra o `content` cru. Recusar é melhor que sair só o corpo, em silêncio.
  UNSUPPORTED_CHANNELS = {
    'Channel::Email' => 'Mensagem com formato especial ainda não pode ser enviada por e-mail. Escreva o link no texto.',
    'Channel::WebWidget' => 'Mensagem com formato especial ainda não pode ser enviada pelo chat do site. Escreva o link no texto.'
  }.freeze

  module_function

  # A mensagem traz a chave `rich_message`, com qualquer valor (vazio também conta: é formato inválido, não texto).
  def rich?(message)
    message.content_attributes.key?(KEY)
  end

  # O mesmo critério do envio: só mensagem de saída (ou modelo) que não é nota privada vai ao canal.
  def goes_to_channel?(message)
    !message.private? && (message.outgoing? || message.template?)
  end

  # O que o agente pode fazer com um tipo numa caixa, antes de montar a mensagem:
  #   :native   sai o formato (WhatsApp oficial com a janela aberta);
  #   :text     o painel converte em texto sozinho; pode mandar `rich_message`;
  #   :refused  não mande `rich_message`; ponha o conteúdo no texto.
  # Decide só por caixa, tipo e janela (o conteúdo continua em `format_error`), com as mesmas regras da trava.
  # Sem `conversation` a janela é desconhecida: nunca responde :native, e tipo sem versão em texto no WhatsApp
  # oficial é :refused, porque a trava o recusaria se a janela estivesse fechada. Custo: a leitura da caixa e,
  # com `conversation`, uma consulta da janela.
  def delivery_mode(inbox:, type:, conversation: nil)
    klass = type_class(type)
    return :refused if klass.nil? || UNSUPPORTED_CHANNELS.key?(inbox.channel_type) || text_channel_error(klass, inbox)
    return :text unless whatsapp_cloud?(inbox)

    whatsapp_cloud_mode(klass, inbox, conversation.present? && window_open?(conversation))
  end

  def whatsapp_cloud_mode(klass, inbox, window_open)
    return :refused if window_refused?(klass, inbox, window_open)

    window_open ? :native : :text
  end

  # O formato da mensagem, ou nil quando ela não tem `rich_message` ou o tipo não existe.
  def build(message)
    type_class_of(message)&.new(message.content_attributes[KEY])
  end

  def type_class_of(message)
    payload = message.content_attributes[KEY]
    type_class(payload['type']) if payload.is_a?(Hash)
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

  # A única fonte de "o tipo tem versão em texto": o método de classe opcional, com padrão verdadeiro.
  def text_version?(klass)
    !klass.respond_to?(:text_version?) || klass.text_version?
  end

  # A mensagem pode sair em texto: não tem `rich_message` (só uma checagem de chave), ou o tipo dela existe e tem
  # versão em texto. Falso para tipo sem versão em texto e para tipo que não existe: nenhum transporte de texto
  # (plano B do Híbrido) pode mandar só o corpo deles.
  def text_capable?(message)
    return true unless rich?(message)

    klass = type_class_of(message)
    klass.present? && text_version?(klass)
  end

  # Por que esta mensagem não pode sair, em texto para o atendente; nil quando pode (ou não tem `rich_message`).
  def error_for(message)
    format_error(message) || window_error(message)
  end

  # A parte que não depende do momento: combinação proibida, canal que não mostra o formato, tipo desconhecido,
  # entrada do tipo fora do contrato e tipo sem versão em texto num canal que não é o WhatsApp oficial. É o que
  # a criação pela API recusa na hora.
  def format_error(message)
    return unless rich?(message)

    combination_error(message) || UNSUPPORTED_CHANNELS[message.inbox.channel_type] || type_error(message)
  end

  # Grava a falha com o motivo. Sem as validações do modelo: a de rajada (`prevent_message_flooding`) recusaria
  # a gravação numa conversa movimentada, e a mensagem ficaria como enviada. O evento de atualização sai igual.
  def fail!(message, error)
    message.assign_attributes(status: :failed, external_error: error)
    message.save!(validate: false)
  end

  # O corpo como o canal o recebe, sem nada do formato.
  def body_text(message)
    MessageContentPresenter.new(message).outgoing_content
  end

  # Corpo + versão em texto do tipo, com uma linha em branco entre os dois. `html: true` escapa o complemento.
  def text_with_fallback(message, body, html: false)
    complement = build(message)&.fallback_text(body)
    return body if complement.blank?

    [body.presence, html ? CGI.escapeHTML(complement) : complement].compact.join("\n\n")
  end

  def html_channel?(inbox)
    HTML_RENDERERS.include?(Messages::MarkdownRendererService::CHANNEL_RENDERERS[inbox.channel_type])
  end

  def whatsapp_cloud?(inbox)
    inbox.channel_type == 'Channel::Whatsapp' && inbox.channel.provider == 'whatsapp_cloud'
  end

  def window_open?(conversation)
    Conversations::MessageWindowService.new(conversation).can_reply?
  end

  def combination_error(message)
    return WITH_TEMPLATE if message.additional_attributes.to_h['template_params'].present?
    return NOT_PLAIN_TEXT unless message.content_type == 'text'

    WITH_ATTACHMENT if message.attachments.present?
  end

  def type_error(message)
    rich = build(message)
    return UNKNOWN_TYPE if rich.nil?

    rich.error_for(body_text(message)) || text_channel_error(rich.class, message.inbox)
  end

  # Tipo sem versão em texto fora do WhatsApp oficial: nenhum canal o mostra.
  def text_channel_error(klass, inbox)
    NO_TEXT_VERSION unless text_version?(klass) || whatsapp_cloud?(inbox)
  end

  # Tipo sem versão em texto no WhatsApp oficial com a janela fechada (ou desconhecida): nenhum transporte de
  # texto (WhatsApp Híbrido) pode levá-lo.
  def window_refused?(klass, inbox, window_open)
    !window_open && !text_version?(klass) && whatsapp_cloud?(inbox)
  end

  # Na trava, o mesmo caso falha com o erro de janela em vez de sair só o corpo.
  def window_error(message)
    klass = type_class_of(message)
    return if klass.nil? || text_version?(klass) || !whatsapp_cloud?(message.inbox)
    return unless window_refused?(klass, message.inbox, window_open?(message.conversation))

    I18n.t('errors.whatsapp.message_outside_messaging_window')
  end
end
