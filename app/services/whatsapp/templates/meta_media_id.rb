# O arquivo do topo (e de cada cartão do carrossel) vai à Meta pelo id da mídia, não pelo link (#2367). Pelo link, a Meta
# baixa o arquivo do nosso armazenamento e essa busca falha de forma intermitente com 131053 ("Downloading media from
# weblink failed with http code 400"); a conversa comum já sobe o arquivo e manda o id (`Whatsapp::MediaUploadService`).
# Sobe na caixa que envia: o id vale para o número da caixa (phone_number_id). O mesmo arquivo na mesma caixa sobe uma
# vez e o id fica guardado (`CACHE_TTL`): a queda da conversa aberta, o reenvio e o carrossel da conversa não sobem de
# novo a cada pessoa.
# Sem id (subida desligada por WHATSAPP_MEDIA_UPLOAD_STRATEGY=link, recusada pela Meta ou com erro), segue pelo link, como
# a conversa comum; a falha fica no log e nunca para o envio.
module Whatsapp::Templates::MetaMediaId
  # A Meta guarda a mídia subida por 30 dias (documentação "Media", lida em 29/10/2026); o id guardado vence bem antes.
  CACHE_TTL = 7.days

  # O `MediaUploadService` lê `attachment.file.blob`, `attachment.file.attached?` e `attachment.id` (só no log).
  BlobFile = Data.define(:blob) do
    def file = self
    def attached? = true
    def id = "blob-#{blob.id}"
  end

  module_function

  # O id da mídia na Meta, ou nil.
  def upload(blob, inbox)
    channel = inbox&.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    key = cache_key(channel, blob)
    Rails.cache.read(key) || uploaded(channel, blob, key)
  rescue StandardError => e
    Rails.logger.warn("[whatsapp_templates][meta_media_id] upload_failed inbox_id=#{inbox&.id} blob_id=#{blob&.id} error=#{e.class.name}")
    nil
  end

  def uploaded(channel, blob, key)
    media_id = Whatsapp::MediaUploadService.new(channel, BlobFile.new(blob)).perform&.dig('id')
    Rails.cache.write(key, media_id, expires_in: CACHE_TTL) if media_id
    media_id
  end

  # Por número (o id só vale nele) e pelo arquivo (a chave do armazenamento não muda; arquivo novo tem chave nova).
  def cache_key(channel, blob)
    "whatsapp_templates:meta_media_id:#{channel.provider_config['phone_number_id']}:#{blob.key}"
  end

  # O parâmetro de mídia do envio pelo id (`{ type: 'image', image: { id: } }`), ou nil sem id ou com tipo desconhecido.
  def parameter(header)
    id = header['media_id'].to_s.strip
    type = header['media_type'].to_s.downcase
    return if id.blank? || !Whatsapp::Templates::HeaderMedia::MIME_PREFIX.key?(type)

    media = { id: id }
    media[:filename] = header['media_name'] if type == 'document' && header['media_name'].present?
    { :type => type, type.to_sym => media }
  end
end
