# Kit do desenvolvedor (CA-1.6, #1068): página pública, só de leitura, que o dono manda para quem cuida do site.
# Traz o código pronto do botão "Falar no WhatsApp" que avisa o clique (contrato em docs/crm/ponte-lp-atribuicao.md,
# seção 2) e os endereços que precisam estar autorizados no link. Só existe para link do tipo site.
#
# Nada aqui é segredo: o endereço de aviso, o código do link e o número já aparecem no próprio site do cliente.
# rubocop:disable Rails/ApplicationController
class Public::TrackedLinkKitsController < ActionController::Base
  layout false
  around_action :with_account_locale

  SNIPPET_FILE = Rails.root.join('app/views/public/tracked_link_kits/snippet.js.txt')

  def show
    return head :not_found unless @tracked_link&.website?

    @phone = @tracked_link.inbox&.channel.try(:phone_number).to_s.delete('+')
    return head :not_found if @phone.blank?

    @signal_url = "#{ENV.fetch('FRONTEND_URL', request.base_url).to_s.chomp('/')}/l/#{@tracked_link.code}/clicks"
    @snippet = snippet
    response.set_header('X-Robots-Tag', 'noindex, nofollow')
  end

  private

  def with_account_locale(&)
    @tracked_link = Ctwa::TrackedLink.find_by(code: params[:code].to_s.upcase)
    I18n.with_locale(@tracked_link&.account&.locale.presence || I18n.default_locale, &)
  end

  # Os valores entram como literais JSON, com < > & escapados de forma explícita (json_escape): aspas, barras e
  # um "</script>" no texto da mensagem nunca quebram nem fecham o script no site do cliente.
  def snippet
    format(SNIPPET_FILE.read, signal_url: js(@signal_url), whatsapp_url: js("https://wa.me/#{@phone}?text="),
                              message: js(@tracked_link.prefilled_text.to_s), alphabet: js(Ctwa::TrackedLink::CODE_ALPHABET.join))
  end

  def js(value)
    ERB::Util.json_escape(value.to_json)
  end
end
# rubocop:enable Rails/ApplicationController
