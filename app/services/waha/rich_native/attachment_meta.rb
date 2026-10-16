# Prepend em Attachment (chat#1709, rodada 2): o painel recebe as marcas do anexo que o recebimento da caixa WAHA comum
# grava (Waha::RichNative::Inbound::Media): `meta.is_voice_message` (áudio de voz), `meta.is_sticker` (figurinha) e
# `meta.is_view_once` (visualização única). O Chatwoot só leva `meta` no anexo de contato; no de áudio, imagem e vídeo
# o `meta` fica fora do JSON. Só acrescenta quando alguma das marcas existe: sem elas, o JSON fica igual ao da main.
module Waha::RichNative::AttachmentMeta
  MARKS = %w[is_voice_message is_sticker is_view_once].freeze

  def push_event_data
    data = super
    marks = meta.to_h.slice(*MARKS)
    return data if data.nil? || marks.empty?

    data.merge(meta: data[:meta].to_h.merge(marks))
  end
end
