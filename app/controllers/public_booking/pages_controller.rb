# Serves the public, server-rendered HTML shell for the Calendly-style booking
# page at /book/:slug (mirrors Survey::ResponsesController). NO authentication —
# inherits ActionController::Base directly. The Vue app (entrypoint 'public_booking')
# resolves the profile + slots over the Public::Api::V1 JSON endpoints using only
# the opaque slug. We do NOT 404 here on an unknown/disabled slug: the Vue app shows
# a branded-neutral "not found" state via the JSON 404, keeping the HTML shell
# cacheable and leaking nothing on the v1 path (the v2 choice below is an accepted risk).
#
# Página nova (#1189): quando o slug é de uma página v2 com a flag da conta ligada, serve a entrada Vite
# `public_booking_v2` (view `show_v2`); `/b/:code` (link por cliente e de gestão) sempre a v2. Aqui só se escolhe a
# view: os dados vêm da API pública v2, nunca da página HTML. A escolha usa o mesmo `?preview=` da API: o slug-base de
# uma página `per_agent` só existe na prévia, e sem o token ele cairia na v1.
#
# Risco aceito (PLANO-TECNICO §10): a casca escolhida (v2 × v1) e o título revelam que um slug é de página nova. O
# slug é opaco (UUID) e a v1 já respondia 200 para todo slug, então a diferença só confirma o que quem tem o link já
# sabe.
#
# Link curto (#1282): `/a/:name` e `/a/:name/:person` servem sempre a v2. A casca troca o nome curto pelo slug opaco
# (`ShortLink.resolve`) e o entrega à página em `<meta name="booking-slug">`; a API pública continua recebendo só o
# slug. Nome que não existe (ou que a API pública não abriria): a mesma casca, sem slug, e a página mostra "não
# encontrada". Página pausada recebe o slug, como em `/book`: quem tem o link vê o aviso de pausa.
#
# Prévia do link (#1282): as três rotas põem no `<head>` as tags Open Graph da `LinkPreview` — só dados da página,
# nunca do cliente, e neutra quando a página não pode ser marcada. É a mesma revelação do risco aceito acima: a
# prévia de uma página no ar mostra o nome dela a quem já tem o link.
class PublicBooking::PagesController < ActionController::Base
  LANGUAGES = { 'pt' => 'pt-BR', 'en' => 'en' }.freeze
  DEFAULT_LANGUAGE = 'pt-BR'.freeze

  before_action :set_global_config

  def show
    page = request.path.end_with?('/confirm') ? nil : find_page(params[:slug])
    @link_preview = ::Crm::BookingV2::LinkPreview.new(page)
    return if page.blank?

    render_v2(page)
  end

  def short
    page = find_page(::Crm::BookingV2::ShortLink.resolve(params[:name], params[:person]))
    # Só o slug que a API pública abre (no ar, pausada ou em prévia válida): o endereço-base de uma página com um
    # link por pessoa e o link de quem saiu da página não vão para a casca.
    @booking_slug = page&.slug
    @link_preview = ::Crm::BookingV2::LinkPreview.new(page)
    render_v2(page)
  end

  def invite
    @link_preview = ::Crm::BookingV2::LinkPreview.for_invite_code(params[:code])
    render_v2(nil)
  end

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'INSTALLATION_NAME')
    @link_preview_url = "#{::Crm::BookingV2::ShortLink.base_url}#{request.path}"
  end

  def find_page(slug)
    ::Crm::BookingV2::PublicPage.find(slug, preview_token: params[:preview])
  end

  def render_v2(page)
    @page_title = (page&.readable? ? page.profile.title.presence : nil) || @global_config['INSTALLATION_NAME']
    @html_lang = browser_language || account_language(page&.account) || DEFAULT_LANGUAGE
    render :show_v2
  end

  # Primeira língua do navegador ("pt-BR,pt;q=0.9,en;q=0.8" -> "pt-BR"), se for uma das que a página tem.
  def browser_language
    first = request.headers['Accept-Language'].to_s.split(',').first.to_s.split(';').first.to_s.strip.downcase
    LANGUAGES[first.split('-').first.to_s]
  end

  def account_language(account)
    LANGUAGES[account&.locale.to_s.split('_').first.to_s]
  end
end
