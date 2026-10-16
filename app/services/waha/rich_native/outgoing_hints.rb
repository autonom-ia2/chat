# Prepend em WebhookListener, o mais externo (chat#1709, fase 3): na caixa WAHA comum, com a flag `whatsapp_rich_native`,
# o `message_created` de uma mensagem nossa leva ao webhook da caixa dois pedidos ao conector customizado (c2y-rich-2):
# - `waha_text`: o texto já no formato do WhatsApp, pelo MESMO renderer da Cloud (Messages::MarkdownRendererService com
#   'Channel::Whatsapp'). O conector usa este texto em vez do conversor próprio dele (que não segue as regras do editor:
#   ~x~, crases, citação de várias linhas, marcador colado em palavra). Mensagem rica que sai como texto leva o corpo
#   mais a versão em texto do tipo, o mesmo que o RichMessages::ApiInboxWebhook manda em `content`.
# - `waha_media_as_media: true`: há foto ou vídeo; o conector manda como mídia mesmo fora de JPG/PNG/MP4 (converte), em
#   vez de arquivo.
# Nada disso é gravado (Waha::RichNative::ContractGuard e ForgeryGuard tiram as duas chaves). Sem a flag, em outra caixa,
# em nota ou no `message_updated`, o payload segue igual. Um motor sem o patch ignora as chaves. Erro aqui: segue sem
# as chaves (o texto de antes), nunca derruba a entrega.
module Waha::RichNative::OutgoingHints
  CHANNEL = 'Channel::Whatsapp'.freeze
  MEDIA_TYPES = %w[image video].freeze

  # O texto no formato do WhatsApp (também usado na edição pelo painel, Waha::RichNative::MessageActions).
  def self.whatsapp_text(text)
    Messages::MarkdownRendererService.new(text.to_s, CHANNEL).render.to_s
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
    text = waha_base_text(message, payload[:content].to_s)
    hints['waha_text'] = Waha::RichNative::OutgoingHints.whatsapp_text(text) if message.content_type == 'text' && text.present?
    hints['waha_media_as_media'] = true if message.attachments.any? { |attachment| MEDIA_TYPES.include?(attachment.file_type.to_s) }
    hints
  end

  def waha_base_text(message, content)
    return content unless RichMessages.rich?(message) && !Waha::RichNative.sent_native?(message)

    RichMessages.text_with_fallback(message, content)
  end
end
