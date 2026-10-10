# Painel de resultados do agendamento (#1194, F2-C, J7, J8-A12). Atrás da flag da conta (`crm_booking_v2`, 404
# desligada) e da `Crm::BookingStatsPolicy`.
#
#   GET  booking_stats?period=7|30&scope=mine|team                      cinco números + origem, sem dado pessoal
#   GET  booking_stats/opened_not_booked?period=&scope=&page=           quem abriu o link e não marcou
#   POST booking_stats/opened_not_booked/:invite_id/resend              "Enviar de novo" (toque do agente)
#
# `scope` padrão: equipe para quem pode vê-la (administrador ou `agendamento_view`), senão "mine". Pedir `team` sem
# a permissão = 401. Período inválido = 422 `crm.booking_v2.invalid_period`; escopo inválido, `invalid_scope`.
class Api::V1::Accounts::Crm::BookingStatsController < Api::V1::Accounts::Crm::BaseController
  SCOPES = %w[mine team].freeze

  before_action :ensure_booking_v2_enabled
  before_action :authorize_stats
  before_action :authorize_team_scope, except: :resend

  rescue_from ::Crm::BookingV2::InviteError do |error|
    render_unprocessable("crm.booking_v2.#{error.message}")
  end

  def show
    results = ::Crm::BookingV2::Results.new(account: Current.account, period: period, user: scoped_user)
    render json: {
      period: period.as_json, scope: scope_name, can_see_team: team_allowed?,
      totals: results.totals, origins: results.origins
    }
  end

  def opened_not_booked
    list = opened_list(period: period, page: params[:page])
    can_send = resend_allowed?
    rows = list.rows.map { |row| row.merge(can_resend: can_send && row[:can_resend]) }
    render json: { scope: scope_name, payload: rows, meta: list.meta.merge(can_resend: can_send) }
  end

  # Reenvio: quem vê a equipe reenvia qualquer link da lista; os demais, só os próprios.
  def resend
    invite = opened_list(user: team_allowed? ? nil : Current.user).candidates.find(params[:invite_id])
    conversation = ::Crm::BookingV2::OpenedNotBooked.resend_conversation(invite)
    authorize conversation, :show? if conversation
    card = invite.card if visibility.card_visible?(invite.card)
    fresh = ::Crm::BookingV2::InviteResender.new(invite: invite, user: Current.user, conversation: conversation, card: card).perform
    render json: { payload: { id: invite.id, resent_at: fresh.sent_at.iso8601 } }
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def authorize_stats
    authorize :booking_stats, "#{action_name}?", policy_class: ::Crm::BookingStatsPolicy
  end

  def authorize_team_scope
    authorize :booking_stats, :team?, policy_class: ::Crm::BookingStatsPolicy if scope_name == 'team'
  end

  def team_allowed?
    stats_policy.team?
  end

  # A lista só oferece "Enviar de novo" a quem pode mandar o link (a mesma régua do POST resend).
  def resend_allowed?
    stats_policy.resend?
  end

  def stats_policy
    @stats_policy ||= ::Crm::BookingStatsPolicy.new(pundit_user, :booking_stats)
  end

  def scope_name
    @scope_name ||= begin
      requested = params[:scope].presence || (team_allowed? ? 'team' : 'mine')
      raise ::Crm::BookingV2::InviteError, 'invalid_scope' unless SCOPES.include?(requested)

      requested
    end
  end

  def scoped_user
    scope_name == 'mine' ? Current.user : nil
  end

  def period
    @period ||= ::Crm::BookingV2::ResultsPeriod.new(account: Current.account, days: params[:period])
  end

  def visibility
    @visibility ||= ::Crm::BookingV2::ClientVisibility.new(account: Current.account, user: Current.user,
                                                           account_user: Current.account_user)
  end

  def opened_list(period: nil, page: 1, user: scoped_user)
    ::Crm::BookingV2::OpenedNotBooked.new(account: Current.account, visibility: visibility, period: period,
                                          user: user, page: page)
  end
end
