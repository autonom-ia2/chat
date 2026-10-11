# O que vai na imagem de prévia de uma página (#1282), a partir da `LinkPreview`: qual dos três desenhos, os textos
# e as imagens (logo da página, foto de quem atende).
#
# `version` é a impressão digital de tudo que aparece no desenho. Ela vai no endereço da imagem: mudou a marca, o
# nome ou o local, o endereço muda, e quem mostra a prévia busca a imagem nova em vez de reusar a antiga.
# `record` é onde a imagem pronta fica guardada: o link da pessoa ou a página.
class Crm::BookingV2::PreviewImage::Content
  # Muda quando o desenho muda, para as imagens guardadas serem refeitas.
  RENDER_VERSION = 1
  IMAGE_TYPES = Crm::BookingPageSettings::IMAGE_TYPES
  MAX_SOURCE_BYTES = 15.megabytes
  VERSION_LENGTH = 20

  def initialize(preview)
    @preview = preview
    @page = preview.page
  end

  def record
    page.link || page.profile
  end

  def design
    @design ||= if page.link && usable?(host_photo)
                  :person
                elsif usable?(profile.logo) || usable?(profile.photo)
                  :brand
                else
                  :light
                end
  end

  def version
    parts = [RENDER_VERSION, design, color, preview.title, preview.call, preview.host_line, preview.facts, sources.map { |blob| blob&.checksum }]
    Digest::SHA256.hexdigest(parts.to_json).first(VERSION_LENGTH)
  end

  def art
    logo, photo = sources.map { |attachment| attachment&.download }
    ::Crm::BookingV2::PreviewImage::Art.new(design: design, color: color, title: preview.title.to_s, call: preview.call,
                                            host_line: preview.host_line, facts: preview.facts, logo: logo, photo: photo)
  end

  private

  attr_reader :preview, :page

  def profile
    page.profile
  end

  def color
    profile.brand.to_h['color'].to_s
  end

  def host_photo
    page.host&.avatar
  end

  # [logo, foto] que o desenho escolhido usa; nil no que ele não usa.
  def sources
    case design
    when :person then [nil, host_photo]
    when :brand then usable?(profile.logo) ? [profile.logo, nil] : [nil, profile.photo]
    else [nil, nil]
    end
  end

  def usable?(attachment)
    attachment.present? && attachment.attached? && IMAGE_TYPES.include?(attachment.content_type) && attachment.byte_size <= MAX_SOURCE_BYTES
  end
end
