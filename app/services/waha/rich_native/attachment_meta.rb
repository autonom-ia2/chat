# Prepend em Attachment (chat#1709, rodada 2): o painel recebe as marcas do anexo que o recebimento da caixa WAHA comum
# grava (Waha::RichNative::Inbound::Media): `meta.is_voice_message` (áudio de voz), `meta.is_sticker` (figurinha) e
# `meta.is_view_once` (visualização única). O Chatwoot só leva `meta` no anexo de contato; no de áudio, imagem e vídeo
# o `meta` fica fora do JSON.
# Só acrescenta quando alguma das marcas existe E o anexo é de mensagem da caixa WAHA comum de conta com a flag
# `whatsapp_rich_native`. O upstream já grava `meta.is_voice_message` no áudio gravado pelo painel em qualquer canal
# (Messages::MessageBuilder#tag_voice_message): fora dessa caixa e sem a flag, o JSON (ActionCable, API e webhooks)
# fica igual ao da main.
module Waha::RichNative::AttachmentMeta
  MARKS = %w[is_voice_message is_sticker is_view_once].freeze

  def push_event_data
    data = super
    return data if data.nil?

    marks = meta.to_h.slice(*MARKS)
    return data if marks.empty? || !waha_rich_native_marks?

    data.merge(meta: data[:meta].to_h.merge(marks))
  end

  private

  def waha_rich_native_marks?
    message.present? && Waha::RichNative::Inbound.waha_inbox?(message) && Waha::RichNative.enabled?(account)
  end
end
