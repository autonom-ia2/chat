# Prévia de link igual ao WhatsApp (#1702). Dois lados:
# - envio: texto comum do atendente com endereço sai com `preview_url: true` na Cloud API
#   (ConversaCanal::PreviaDeLinkNoEnvio), e o celular do cliente monta a prévia;
# - painel: a Meta não manda a prévia, então o servidor lê o Open Graph do primeiro endereço
#   (ConversaCanal::LeitorDeOpenGraph, pelo SafeFetch) e grava em `content_attributes.link_preview`.
# O endereço é o mesmo que o WhatsApp usa: o PRIMEIRO do texto, começando com http:// ou https://
# (RichMessages::Types::LinkPreview.first_web_address). Tudo só com a chave `conversa_cara_do_canal`.
module ConversaCanal::PreviaDeLink
  CHAVE = 'link_preview'.freeze
  FLAG = ConversaCanal::Pele::FLAG
  TIPOS_DA_MENSAGEM = %w[incoming outgoing].freeze

  module_function

  def endereco(texto)
    RichMessages::Types::LinkPreview.first_web_address(texto)
  end

  # A conta tem a chave ligada e a caixa é WhatsApp (oficial, que inclui a híbrida, ou API com WAHA) — o mesmo
  # critério da tela (conversa-canal/pele.js). Twilio fica de fora.
  def ligada?(inbox)
    return false unless inbox&.account&.feature_enabled?(FLAG)

    channel = inbox.channel
    channel.is_a?(Channel::Whatsapp) || (channel.is_a?(Channel::Api) && channel.waha_provider?)
  end

  # Mensagem que ganha a prévia no painel: do cliente ou da empresa, nunca nota (o texto da nota não sai do
  # painel), texto puro sem anexo (no WhatsApp a legenda de foto não ganha prévia) e com endereço válido.
  def buscar?(message)
    ligada?(message.inbox) && tipo_que_ganha_previa?(message) && sem_previa_ainda?(message) &&
      texto_comum_ou_previa?(message) && cliente_viu_o_cartao?(message) && endereco(message.content).present?
  end

  # O painel só mostra o cartão que o cliente também viu. A recebida traz o cartão do app de quem mandou. A enviada só
  # o ganha quando sai como texto comum pela Cloud API com `preview_url` (ConversaCanal::PreviaDeLinkNoEnvio): modelo,
  # campanha e envio pelo WAHA (linkPreview desligado) chegam ao cliente sem cartão. A enviada pelo celular da empresa
  # (eco da coexistência) passa: o app monta a prévia.
  def cliente_viu_o_cartao?(message)
    return true if message.incoming?

    return false if ConversaCanal::Pele.modelo_ou_campanha?(message)

    channel = message.inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def tipo_que_ganha_previa?(message)
    !message.private? && TIPOS_DA_MENSAGEM.include?(message.message_type) &&
      message.content_type == 'text' && message.attachments.none?
  end

  # Importação de histórico não dispara nada de mensagem nova; prévia já gravada não é buscada de novo.
  def sem_previa_ainda?(message)
    !message.content_attributes['history_import'] && !message.content_attributes.key?(CHAVE)
  end

  # Mensagem rica só ganha a prévia se for a própria prévia de link; botões e opções aparecem como no app.
  def texto_comum_ou_previa?(message)
    return true unless RichMessages.rich?(message)

    RichMessages.type_class_of(message) == RichMessages::Types::LinkPreview
  end
end
