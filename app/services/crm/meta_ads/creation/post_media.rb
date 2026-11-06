# A foto ou o vídeo do post (#2198 PR 3, #2653). Post não usa a biblioteca da conta de anúncios: a Meta busca o
# arquivo num endereço temporário do nosso armazenamento, na Página e no Instagram. Por isso a mídia sobe uma vez e
# vale para as duas redes e para o "Tentar de novo".
#
# - Mesmos limites e conferência do arquivo do anúncio (Crm::MetaAds::Creation::Media.kind!).
# - O Instagram só aceita foto JPEG: PNG vira JPEG aqui, e a Página recebe a mesma.
# - Volta um `signed_id` que só vale nesta conta e por um dia; o arquivo é apagado depois disso.
class Crm::MetaAds::Creation::PostMedia
  KEEP = 1.day
  JPEG_TYPE = 'image/jpeg'.freeze

  def initialize(account)
    @account = account
  end

  def upload!(file)
    kind = Crm::MetaAds::Creation::Media.kind!(file)
    Crm::MetaAds::Creation::Media.frontend_host!
    blob = kind == 'image' ? store_image(file) : store(File.open(file.path), file.original_filename.presence || 'video.mp4', file.content_type)
    ActiveStorage::PurgeJob.set(wait: KEEP).perform_later(blob)
    { kind: kind, signed_id: blob.signed_id(purpose: purpose, expires_in: KEEP) }
  end

  # { kind:, url: } do arquivo subido por `upload!` nesta conta. Outro, vencido ou apagado: `invalid_media`.
  def find!(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s, purpose: purpose)
    raise Crm::MetaAds::Creation::Error, 'invalid_media' unless blob

    host = Crm::MetaAds::Creation::Media.frontend_host!
    { kind: blob.content_type == JPEG_TYPE ? 'image' : 'video', url: Crm::MetaAds::Creation::Media.public_url(blob, host) }
  end

  private

  def purpose
    "meta_ads_post_media_#{@account.id}"
  end

  def store_image(file)
    return store(File.open(file.path), 'post.jpg', JPEG_TYPE) if file.content_type.to_s == JPEG_TYPE

    store(jpeg(file.path), 'post.jpg', JPEG_TYPE)
  end

  def jpeg(path)
    ImageProcessing::Vips.source(path).convert('jpg').saver(quality: 90).call
  end

  def store(io, filename, content_type)
    ActiveStorage::Blob.create_and_upload!(io: io, filename: filename, content_type: content_type)
  end
end
