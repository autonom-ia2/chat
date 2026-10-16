# `waha_media` (chat#1709, rodada 2): o que o conector sabe da mídia que ele anexou, { kind: voice | audio | image |
# video | document | sticker, mimetype, filename, ptt, view_once, animated, lottie }. Muda só os anexos da mensagem
# nova (ainda em memória, antes do INSERT):
# - voz (PTT): `meta.is_voice_message` no anexo de áudio, que o player do painel toca como mensagem de voz, e o nome
#   'no-filename.oga' do conector vira 'audio-<data e hora no fuso da conta>.ogg';
# - figurinha: anexo de imagem com `meta.is_sticker`, nome 'sticker.webp' e sem texto (a bolha de imagem exige
#   `content` vazio);
# - visualização única que chegou: `meta.is_view_once` (a mídia fica gravada e visível, decisão do Rodrigo).
# As marcas vão ao painel por Waha::RichNative::AttachmentMeta. O nome só muda quando o conector não deu nome (começa
# com NO_NAME_PREFIX).
module Waha::RichNative::Inbound::Media
  NO_NAME_PREFIX = 'no-filename'.freeze
  STICKER_NAME = 'sticker.webp'.freeze
  MEDIA_TYPES = %w[image audio video file].freeze

  module_function

  def apply(message, data)
    return unless data.is_a?(Hash)

    attachments = message.attachments.select { |attachment| MEDIA_TYPES.include?(attachment.file_type.to_s) }
    case data['kind']
    when 'voice' then voice!(message, attachments.select { |attachment| attachment.file_type.to_s == 'audio' })
    when 'sticker' then sticker!(message, attachments)
    end
    mark!(attachments, 'is_view_once') if data['view_once'] == true
  end

  def voice!(message, attachments)
    mark!(attachments, 'is_voice_message')
    attachments.each { |attachment| rename!(attachment, voice_name(message)) }
  end

  def sticker!(message, attachments)
    return if attachments.empty?

    attachments.each do |attachment|
      attachment.file_type = :image
      rename!(attachment, STICKER_NAME)
    end
    mark!(attachments, 'is_sticker')
    message.content = nil
  end

  def mark!(attachments, key)
    attachments.each { |attachment| attachment.meta = attachment.meta.to_h.merge(key => true) }
  end

  # O blob do upload ainda não foi gravado: trocar o nome em memória vale para o arquivo enviado ao storage.
  def rename!(attachment, name)
    blob = attachment.attachment_changes['file']&.blob
    return if blob.nil? || !blob.new_record? || !blob.filename.to_s.start_with?(NO_NAME_PREFIX)

    blob.filename = name
  end

  # A hora no fuso da conta (o mesmo do CRM e do painel).
  def voice_name(message)
    zone = Crm::Timezone::Resolver.new(account: message.account).zone_or_default
    "audio-#{Time.current.in_time_zone(zone).strftime('%Y%m%d-%H%M%S')}.ogg"
  end
end
