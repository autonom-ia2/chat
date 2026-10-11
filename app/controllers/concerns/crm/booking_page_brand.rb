# A marca da página de agendamento, fora do BookingPagesController para ele caber no tamanho de classe do repo: enviar
# logo e foto (#1187), a logo para fundo escuro (#1295) e a identidade salva (#1289) — usar a identidade da conta numa
# página e salvar a identidade a partir de uma página. Logo, cor, lado da logo e frase são da conta; a foto é de quem
# atende (`Crm::BookingV2::BrandIdentity`).
module Crm::BookingPageBrand
  extend ActiveSupport::Concern

  # Trocar a logo gera de novo a de fundo escuro, a não ser que a pessoa tenha enviado a dela.
  def logo
    upload do |file|
      @page.update!(logo: file)
      ::Crm::BookingV2::LogoDark.new(@page).refresh!
    end
  end

  # Só com a logo já enviada: sem ela a página não mostra logo nenhuma, e a de fundo escuro ficaria solta.
  def logo_dark
    return render_unprocessable('crm.booking_v2.logo_missing') unless @page.logo.attached?

    upload { |file| ::Crm::BookingV2::LogoDark.new(@page).upload!(file) }
  end

  # Tira a logo de fundo escuro que a pessoa enviou e volta para a gerada pelo sistema.
  def destroy_logo_dark
    ::Crm::BookingV2::LogoDark.new(@page).remove_upload!
    render_page
  end

  def photo
    upload { |file| @page.update!(photo: file) }
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

  def upload
    file = params[:file]
    return render_unprocessable('crm.booking_v2.file_missing') unless file.is_a?(ActionDispatch::Http::UploadedFile)

    yield file
    render_page
  end

  # O formulário manda `brand` inteiro (cor, frase, lado da logo). De onde veio a logo de fundo escuro é o servidor
  # quem guarda ali, e não pode sumir quando a pessoa salva o resto. Quem chama trava a página antes (`with_lock`
  # relê o registro), para valer a origem que está no banco e não a de quando o pedido começou.
  def keep_logo_dark_source(attributes)
    return attributes unless attributes.key?('brand')

    kept = @page.brand.to_h.slice(::Crm::BookingV2::LogoDark::SOURCE_KEY)
    attributes.merge('brand' => kept.merge(attributes['brand']))
  end

  # Página com logo de antes do #1295 ainda não tem a de fundo escuro: ganha na primeira vez que for salva.
  def ensure_logo_dark
    generator = ::Crm::BookingV2::LogoDark.new(@page)
    generator.refresh! if generator.pending?
  end
end
