# Foto e vídeo do celular para o anúncio (#2198, Fluxo 1). Os limites da tela são nossos e valem de novo aqui: foto JPG
# ou PNG até 30 MB, vídeo MP4 ou MOV até 1 GB.
#
# - Foto: vai em base64 para /act_{id}/adimages e volta com o `hash` que o criativo usa.
# - Vídeo: fica no armazenamento da plataforma, e a Meta o busca por um endereço temporário (/advideos com `file_url`).
#   A Meta processa sozinha; o criar confere se ficou pronto. O arquivo é apagado daqui a um dia.
class Crm::MetaAds::Creation::Media
  IMAGE_TYPES = %w[image/jpeg image/png].freeze
  VIDEO_TYPES = %w[video/mp4 video/quicktime].freeze
  IMAGE_MAX_BYTES = 30.megabytes
  VIDEO_MAX_BYTES = 1.gigabyte
  VIDEO_URL_TTL = 6.hours
  VIDEO_KEEP = 1.day

  def initialize(connection)
    @connection = connection
    @client = Crm::MetaAds::Creation::Access.new(connection).client
  end

  # Assinatura do começo do arquivo: o tipo que o navegador diz não basta.
  JPEG_START = "\xFF\xD8\xFF".b.freeze
  PNG_START = "\x89PNG\r\n\x1A\n".b.freeze
  # MP4 e MOV: a primeira caixa (a partir do 5º byte) é uma destas.
  VIDEO_BOXES = %w[ftyp moov wide mdat free skip].freeze

  def upload!(file)
    type = file.content_type.to_s
    return image!(file) if IMAGE_TYPES.include?(type) && image_bytes?(file)
    return video!(file) if VIDEO_TYPES.include?(type) && video_bytes?(file)

    raise Crm::MetaAds::Creation::Error, 'invalid_media'
  end

  private

  def image!(file)
    raise Crm::MetaAds::Creation::Error, 'media_too_large' if file.size > IMAGE_MAX_BYTES

    result = @client.upload_image(@connection.ad_account_id, Base64.strict_encode64(File.binread(file.path)))
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok

    image = result.data['images'].to_h.values.first.to_h
    raise Crm::MetaAds::Creation::Error, 'meta_refused' if image['hash'].blank?

    { kind: 'image', hash: image['hash'], url: image['url'], width: image['width'], height: image['height'] }
  end

  def video!(file)
    raise Crm::MetaAds::Creation::Error, 'media_too_large' if file.size > VIDEO_MAX_BYTES

    host = frontend_host!

    blob = ActiveStorage::Blob.create_and_upload!(io: File.open(file.path), filename: file.original_filename.presence || 'video.mp4',
                                                  content_type: file.content_type)
    ActiveStorage::PurgeJob.set(wait: VIDEO_KEEP).perform_later(blob)
    result = @client.upload_video(@connection.ad_account_id, public_url(blob, host))
    raise Crm::MetaAds::Creation::Error.from_result(result) unless result.ok && result.data['id'].present?

    { kind: 'video', video_id: result.data['id'].to_s }
  end

  def head(file, size)
    File.open(file.path, 'rb') { |io| io.read(size).to_s }
  end

  def image_bytes?(file)
    start = head(file, PNG_START.bytesize)
    start.start_with?(JPEG_START) || start == PNG_START
  end

  def video_bytes?(file)
    VIDEO_BOXES.include?(head(file, 8).byteslice(4, 4))
  end

  # O endereço da plataforma, para o armazenamento em disco montar a URL. Sem ele, a Meta receberia um endereço que não
  # alcança: falha antes de guardar o vídeo, e o erro vai para o rastreador (é configuração, não escolha da pessoa).
  def frontend_host!
    ENV.fetch('FRONTEND_URL', '').presence || raise(ArgumentError, 'FRONTEND_URL vazio: o vídeo do anúncio não teria endereço')
  end

  # Endereço direto do armazenamento (no S3, assinado e com prazo), que a Meta lê sem login.
  def public_url(blob, host)
    ActiveStorage::Current.set(url_options: { host: host }) do
      blob.url(expires_in: VIDEO_URL_TTL)
    end
  end
end
