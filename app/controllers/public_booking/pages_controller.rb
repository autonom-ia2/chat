# Serves the public, server-rendered HTML shell for the Calendly-style booking
# page at /book/:slug (mirrors Survey::ResponsesController). NO authentication —
# inherits ActionController::Base directly. The Vue app (entrypoint 'public_booking')
# resolves the profile + slots over the Public::Api::V1 JSON endpoints using only
# the opaque slug. We do NOT 404 here on an unknown/disabled slug: the Vue app shows
# a branded-neutral "not found" state via the JSON 404, keeping the HTML shell
# cacheable and leaking nothing.
#
# Página nova (#1189): quando o slug é de uma página v2 com a flag da conta ligada, serve a entrada Vite
# `public_booking_v2` (view `show_v2`); `/b/:code` (link por cliente e de gestão) sempre a v2. Aqui só se escolhe a
# view: os dados vêm da API pública v2, nunca da página HTML.
class PublicBooking::PagesController < ActionController::Base
  LANGUAGES = { 'pt' => 'pt-BR', 'en' => 'en' }.freeze
  DEFAULT_LANGUAGE = 'pt-BR'.freeze

  before_action :set_global_config

  def show
    page = request.path.end_with?('/confirm') ? nil : ::Crm::BookingV2::PublicPage.find(params[:slug])
    return if page.blank?

    @page_title = page.readable? ? page.profile.title.presence : nil
    render_v2(account: page.account)
  end

  def invite
    render_v2(account: nil)
  end

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'INSTALLATION_NAME')
  end

  def render_v2(account:)
    @page_title = @page_title.presence || @global_config['INSTALLATION_NAME']
    @html_lang = browser_language || account_language(account) || DEFAULT_LANGUAGE
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
