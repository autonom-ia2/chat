class ApplicationController < ActionController::Base
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include Pundit::Authorization
  include SwitchLocale
  include TrackSessionActivity

  skip_before_action :verify_authenticity_token

  before_action :set_current_user, unless: :devise_controller?
  around_action :switch_locale
  around_action :handle_with_exception, unless: :devise_controller?

  private

  # O Rails trata o `rescue_from` por fora dos `around_action` (ActionController::Rescue#process_action): quando o
  # handler roda, o `I18n.with_locale` do idioma já terminou, e a mensagem sairia no idioma padrão (#2110). Aqui o
  # handler roda no último idioma que o pedido abriu (SwitchLocale#set_locale), sem consultar nada de novo.
  def rescue_with_handler(exception)
    I18n.with_locale(@request_locale) { super }
  end

  def set_current_user
    @user ||= current_user
    Current.user = @user
  end

  def pundit_user
    {
      user: Current.user,
      account: Current.account,
      account_user: Current.account_user
    }
  end
end
ApplicationController.include_mod_with('Concerns::ApplicationControllerConcern')
