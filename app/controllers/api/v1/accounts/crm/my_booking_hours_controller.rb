# "Meus horários" (#1195, J8-A11): a própria pessoa vê e ajusta os dias e horas em que aceita reuniões das páginas
# novas, dentro dos limites delas, e pausa a própria agenda. Atrás da flag da conta (`crm_booking_v2`, 404 desligada).
#
# Não pede `agendamento_*`: basta poder atender (`HostEligibility`: administrador, agente sem função, ou função com
# `crm_view`/`crm_admin`). Quem não pode atender recebe 401, o padrão do sistema para Pundit::NotAuthorizedError.
# Só mexe no registro de `Current.user`: não existe parâmetro de pessoa.
class Api::V1::Accounts::Crm::MyBookingHoursController < Api::V1::Accounts::Crm::BaseController
  before_action :ensure_booking_v2_enabled
  before_action :ensure_can_host

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: 'crm.booking_v2.my_hours_invalid', errors: error.record.errors.to_hash }, status: :unprocessable_entity
  end

  def show
    render json: { payload: my_hours.payload }
  end

  def update
    render json: { payload: my_hours.update!(update_params) }
  rescue ::Crm::BookingV2::MyHours::OutsidePage
    render_unprocessable('crm.booking_v2.my_hours_outside_page')
  rescue ::Crm::BookingV2::MyHours::NoPages
    render_unprocessable('crm.booking_v2.my_hours_no_pages')
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def ensure_can_host
    raise Pundit::NotAuthorizedError unless ::Crm::BookingV2::HostEligibility.eligible?(account: Current.account, user: Current.user)
  end

  def my_hours
    @my_hours ||= ::Crm::BookingV2::MyHours.new(account: Current.account, user: Current.user)
  end

  def update_params
    params.permit(:paused, :use_page_hours, working_hours: [:start_hour, :end_hour, { weekdays: [] }]).to_h.symbolize_keys
  end
end
