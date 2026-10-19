# Prepend em WebhookListener, o mais externo (chat#1709, fase 3): na caixa WAHA comum, com a flag `whatsapp_rich_native`,
# o `message_created` de uma mensagem nossa leva ao webhook da caixa dois pedidos ao conector customizado (c2y-rich-2):
# - `waha_text`: o texto já no formato do WhatsApp, pelo MESMO renderer da Cloud (Messages::MarkdownRendererService com
#   'Channel::Whatsapp'). O conector usa este texto em vez do conversor próprio dele (que não segue as regras do editor:
#   ~x~, crases, citação de várias linhas, marcador colado em palavra). Mensagem rica leva SEMPRE o corpo mais a versão
#   em texto do tipo (RichMessages.text_with_fallback), o mesmo `content` que o RichMessages::ApiInboxWebhook manda:
#   quando o motor recusa o envio nativo, o conector manda este texto, que precisa ter as opções numeradas.
#   Só sai quando o renderer do WhatsApp do chat#1740 está no código (`renderer_ready?`). Sem ele, o renderer antigo
#   perderia ~~x~~, as crases do bloco e o # do título: o conector segue com o conversor dele, como hoje.
# - `waha_media_as_media: true`: há foto ou vídeo; o conector manda como mídia mesmo fora de JPG/PNG/MP4 (converte), em
#   vez de arquivo.
# Nada disso é gravado (Waha::RichNative::ContractGuard e ForgeryGuard tiram as duas chaves). Sem a flag, em outra caixa,
# em nota ou no `message_updated`, o payload segue igual. Um motor sem o patch ignora as chaves. Erro aqui: segue sem
# as chaves (o texto de antes), nunca derruba a entrega.
module Waha::RichNative::OutgoingHints
  CHANNEL = 'Channel::Whatsapp'.freeze
  MEDIA_TYPES = %w[image video].freeze

  # O renderer do chat#1740 (blocos cercados sem quebrar a cerca, ~x~, crases contadas, dialeto do robô): é a mesma
  # fonte da Cloud. Enquanto ele não está na main, o `waha_text` não sai e a edição pelo painel fica fora (o conector
  # exige o texto pronto).
  def self.renderer_ready?
    Messages::MarkdownRenderers.const_defined?(:WhatsAppNewlines) && Messages.const_defined?(:EnvioAutomatico)
  end

  # O texto no formato do WhatsApp (também usado na edição pelo painel, Waha::RichNative::MessageActions). Mensagem do
  # robô, da IA ou de envio automático segue o dialeto do WhatsApp (*x* negrito), como na Cloud.
  # `pele: true`: o renderer do chat#1740 na main é o Messages::MarkdownRenderers::WhatsAppDaPeleRenderer, o formato
  # que o app mostra (bloco ``` mono, ~x~, citação em várias linhas, marcador colado em letra fica). É ele que tem
  # paridade com o conversor do conector; o WhatsAppRenderer do Chatwoot (sem a pele) perde isso.
  def self.whatsapp_text(text, message = nil)
    automatico = message.present? && Messages::EnvioAutomatico.automatico?(message)
    Messages::MarkdownRendererService.new(text.to_s, CHANNEL, nil, pele: true, automatico: automatico).render.to_s
  end

  private

  def deliver_api_inbox_webhooks(payload, inbox)
    hints = waha_outgoing_hints(payload, inbox)
    return super if hints.blank?

    super(payload.merge(content_attributes: payload[:content_attributes].to_h.merge(hints)), inbox)
  end

  def waha_outgoing_hints(payload, inbox)
    return unless payload[:event] == 'message_created' && waha_inbox_with_flag?(inbox)

    message = Message.find_by(id: payload[:id])
    return unless message&.outgoing? && !message.private?

    waha_hints_for(message, payload)
  rescue StandardError => e
    Rails.logger.error("[waha] rich native outgoing hints message=#{payload[:id]} #{e.class}")
    nil
  end

  def waha_inbox_with_flag?(inbox)
    inbox.channel_type == 'Channel::Api' && inbox.channel.try(:waha_provider?) && Waha::RichNative.enabled?(inbox.account)
  end

  def waha_hints_for(message, payload)
    hints = {}
    hints['waha_text'] = waha_text_for(message, payload[:content].to_s) if message.content_type == 'text'
    hints['waha_media_as_media'] = true if message.attachments.any? { |attachment| MEDIA_TYPES.include?(attachment.file_type.to_s) }
    hints.compact
  end

  def waha_text_for(message, content)
    return unless Waha::RichNative::OutgoingHints.renderer_ready?

    text = RichMessages.rich?(message) ? RichMessages.text_with_fallback(message, content) : content
    Waha::RichNative::OutgoingHints.whatsapp_text(text, message) if text.present?
  end
end
