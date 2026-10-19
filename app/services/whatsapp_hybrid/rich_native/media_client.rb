# O cliente do motor de um envio de foto fora de JPG/PNG (chat#1709, fase 3, WhatsappHybrid::RichNative::MediaAsMedia).
# Só o `send_media` de `sendImage` muda; se a variante JPEG não puder ser gerada (formato que o processador de imagem
# não lê, ou sem o processador no servidor), segue o pedido original e o log leva só a classe do erro.
class WhatsappHybrid::RichNative::MediaClient < SimpleDelegator
  KEEP = %w[image/jpeg image/png].freeze
  GIF = 'image/gif'.freeze
  JPEG = 'image/jpeg'.freeze
  QUALITY = 85

  def self.rewrite?(attachment)
    attachment.present? && attachment.file_type.to_s == 'image' && attachment.file.attached? &&
      KEEP.exclude?(attachment.file.content_type.to_s)
  end

  # A URL direta (como o `download_url` do anexo) de uma variante JPEG, gerada e guardada pelo ActiveStorage.
  def self.jpeg_variant_url(attachment)
    ActiveStorage::Current.url_options = Rails.application.routes.default_url_options if ActiveStorage::Current.url_options.blank?
    attachment.file.variant(format: :jpeg, saver: { quality: QUALITY }).processed.url
  end

  def initialize(client, attachment)
    super(client)
    @attachment = attachment
  end

  def send_media(kind, media:, **args)
    return __getobj__.send_media(kind, **args, media: media) unless kind == 'sendImage'
    return __getobj__.send_media('sendVideo', **args, media: media) if @attachment.file.content_type == GIF

    url = jpeg_url
    return __getobj__.send_media(kind, **args, media: media) if url.nil?

    __getobj__.send_media(kind, **args, media: media.merge(file: { url: url, mimetype: JPEG, filename: jpeg_filename }))
  end

  private

  # LoadError: o servidor sem a biblioteca de imagem (vips); não é StandardError e derrubaria o envio.
  def jpeg_url
    WhatsappHybrid::RichNative::MediaClient.jpeg_variant_url(@attachment)
  rescue StandardError, LoadError => e
    Rails.logger.warn("[whatsapp_hybrid] jpeg variant failed attachment=#{@attachment.id} #{e.class}")
    nil
  end

  def jpeg_filename
    "#{@attachment.file.filename.base}.jpg"
  end
end
