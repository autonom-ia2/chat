# A marca da página de agendamento, fora do BookingPagesController para ele caber no tamanho de classe do repo: enviar
# logo e foto (#1187), a logo para fundo escuro (#1295), a identidade salva (#1289) — usar a identidade da conta numa
# página e salvar a identidade a partir de uma página — e a foto de quem atende ligada à foto do perfil (#1298). Logo,
# cor, lado da logo e frase são da conta; a foto é de quem atende (`Crm::BookingV2::BrandIdentity`).
module Crm::BookingPageBrand
  extend ActiveSupport::Concern

  # Trocar a logo gera de novo a de fundo escuro, a não ser que a pessoa tenha enviado a dela.
  def logo
    return unless store_upload(:logo)

    ::Crm::BookingV2::LogoDark.new(@page).refresh!
    render_page
  end

  # Só com a logo já enviada: sem ela a página não mostra logo nenhuma, e a de fundo escuro ficaria solta.
  def logo_dark
    return render_unprocessable('crm.booking_v2.logo_missing') unless @page.logo.attached?

    file = uploaded_file
    return if file.nil?

    ::Crm::BookingV2::LogoDark.new(@page).upload!(file)
    render_page
  end

  # Tira a logo de fundo escuro que a pessoa enviou e volta para a gerada pelo sistema.
  def destroy_logo_dark
    ::Crm::BookingV2::LogoDark.new(@page).remove_upload!
    render_page
  end

  # `apply_to_profile` (#1298): a mesma foto vira também a foto do perfil de quem atende. Só vale quando quem envia É
  # essa pessoa; vindo de outra pessoa (o administrador montando a página de alguém) o pedido é ignorado e o perfil
  # alheio não é tocado.
  def photo
    render_page if store_upload(:photo) { apply_photo_to_profile }
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

  # O arquivo enviado, ou nil depois de responder que ele faltou.
  def uploaded_file
    file = upload_params[:file]
    return file if file.is_a?(ActionDispatch::Http::UploadedFile)

    render_unprocessable('crm.booking_v2.file_missing')
    nil
  end

  # Grava o arquivo na página (e o que o bloco fizer, na mesma transação). Falso quando o arquivo faltou.
  def store_upload(name)
    file = uploaded_file
    return false if file.nil?

    ActiveRecord::Base.transaction do
      @page.public_send(:"#{name}=", file)
      @page.save!
      yield if block_given?
    end
    true
  end

  def upload_params
    params.permit(:file, :apply_to_profile)
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

  # O mesmo arquivo (blob) da página vira o avatar: nada é enviado de novo. Sem as validações do usuário de propósito:
  # a foto já passou pela regra da página (PNG, JPEG ou WebP até 2 MB), mais apertada que a do avatar, e um dado
  # antigo inválido no cadastro da pessoa não pode derrubar o envio da foto.
  def apply_photo_to_profile
    return unless upload_params[:apply_to_profile].to_s == 'true' && photo_owner_is_me?

    Current.user.avatar = @page.photo.blob
    Current.user.save!(validate: false)
    @profile_photo_updated = true
  end

  # A pessoa da foto: quem atende a página de uma pessoa só. Página com um link por pessoa não tem uma pessoa só.
  def photo_owner
    brand_identity.host_of(@page)
  end

  def photo_owner_is_me?
    photo_owner.present? && photo_owner.id == Current.user.id
  end

  # Para a tela (#1298): de quem é a foto, se é de quem está vendo (`mine`), a foto do perfil dela e se este envio
  # trocou o perfil (`profile_updated`, para o painel atualizar o avatar sem recarregar). Nulo em página com um link
  # por pessoa.
  def photo_owner_payload
    owner = photo_owner
    return { photo_owner: nil } if owner.blank?

    { photo_owner: { name: owner.name, mine: photo_owner_is_me?, profile_url: owner.avatar_url.presence,
                     profile_updated: @profile_photo_updated == true } }
  end
end
