# Desenha a imagem de prévia (#1282) e devolve os bytes do PNG. Escolhe o desenho pelo `Art#design`.
#
# Logo ou foto que a libvips não consegue ler (arquivo corrompido, grande demais) não derruba a prévia: a página
# ganha o desenho claro, sem imagem, que fica guardado como qualquer outro.
class Crm::BookingV2::PreviewImage::Renderer
  LAYOUTS = {
    brand: 'Crm::BookingV2::PreviewImage::BrandLayout',
    person: 'Crm::BookingV2::PreviewImage::PersonLayout',
    light: 'Crm::BookingV2::PreviewImage::LightLayout'
  }.freeze

  def self.png(art)
    draw(art)
  rescue ::Crm::BookingV2::PreviewImage::Canvas::UnusableImage
    draw(art.with(design: :light, logo: nil, photo: nil))
  end

  def self.draw(art)
    LAYOUTS.fetch(art.design).constantize.new(art).png
  end
  private_class_method :draw
end
