# Link curto da página de agendamento (#1282), para o campo "Endereço da página" do assistente.
#
# `GET booking_pages/short_name`:
# - `?name=`: diz se o nome serve e está livre nesta conta (`available`; `problem` = o que impede);
# - sem `name`, com `?title=`: sugere um nome livre a partir do título;
# - `page_id`: a página que já pode ser a dona do nome (só vale se for uma página nova desta conta).
#
# Atrás da flag da conta (`crm_booking_v2`, 404 desligada), do módulo de função `agendamento` e de
# `Crm::BookingPagePolicy#short_name?`: só quem gerencia páginas (`agendamento_manage`). Desde o #1299 o nome é único
# por conta, e a resposta só fala das páginas da própria conta; o Rack::Attack continua limitando por IP e por conta.
class Api::V1::Accounts::Crm::BookingPageShortNamesController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_booking_v2_enabled
  before_action -> { check_module_permission!('agendamento') }
  before_action :authorize_short_name

  def show
    payload = ::Crm::BookingV2::ShortName.check(params[:name], title: params[:title], account_id: Current.account.id, except_id: own_page_id)
    render json: { payload: payload }
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def authorize_short_name
    authorize(::Crm::AgentBookingProfile, :short_name?, policy_class: ::Crm::BookingPagePolicy)
  end

  def own_page_id
    return if params[:page_id].blank?

    policy_scope(::Crm::AgentBookingProfile, policy_scope_class: ::Crm::BookingPagePolicy::Scope).find_by(id: params[:page_id])&.id
  end
end
