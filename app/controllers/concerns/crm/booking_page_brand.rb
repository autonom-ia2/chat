# A marca da página de agendamento, fora do BookingPagesController para ele caber no tamanho de classe do repo: enviar
# logo e foto (#1187) e a identidade salva (#1289) — usar a identidade da conta numa página e salvar a identidade a
# partir de uma página. Logo, cor, lado da logo e frase são da conta; a foto é de quem atende
# (`Crm::BookingV2::BrandIdentity`).
module Crm::BookingPageBrand
  extend ActiveSupport::Concern

  def logo
    upload(:logo)
  end

  def photo
    upload(:photo)
  end

  def apply_identity
    brand_identity.apply_to!(@page)
    render_page
  end

  def save_identity
    brand_identity.save_from!(@page)
    render_page
  end

  private

  def brand_identity
    ::Crm::BookingV2::BrandIdentity.new(Current.account)
  end

  def upload(name)
    file = params[:file]
    return render_unprocessable('crm.booking_v2.file_missing') unless file.is_a?(ActionDispatch::Http::UploadedFile)

    @page.public_send(:"#{name}=", file)
    @page.save!
    render_page
  end
end
