# A marca da página de agendamento, fora do BookingPagesController para ele caber no tamanho de classe do repo: enviar
# logo e foto (#1187), a identidade salva (#1289) — usar a identidade da conta numa página e salvar a identidade a
# partir de uma página — e a foto de quem atende ligada à foto do perfil (#1298). Logo, cor, lado da logo e frase são
# da conta; a foto é de quem atende (`Crm::BookingV2::BrandIdentity`).
module Crm::BookingPageBrand
  extend ActiveSupport::Concern

  def logo
    upload(:logo)
  end

  # `apply_to_profile` (#1298): a mesma foto vira também a foto do perfil de quem atende. Só vale quando quem envia É
  # essa pessoa; vindo de outra pessoa (o administrador montando a página de alguém) o pedido é ignorado e o perfil
  # alheio não é tocado.
  def photo
    upload(:photo) { apply_photo_to_profile }
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
    file = upload_params[:file]
    return render_unprocessable('crm.booking_v2.file_missing') unless file.is_a?(ActionDispatch::Http::UploadedFile)

    ActiveRecord::Base.transaction do
      @page.public_send(:"#{name}=", file)
      @page.save!
      yield if block_given?
    end
    render_page
  end

  def upload_params
    params.permit(:file, :apply_to_profile)
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
