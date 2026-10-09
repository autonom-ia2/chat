# Link por cliente, lado público (#1190, J1-A2/A6, RA-05): o que a página `/b/<code>` precisa para abrir já
# sabendo quem é o cliente. Sem login: o código opaco é a única autorização, e nenhum id da conta é lido da URL.
#
# 404 UNIFORME (`{ error: 'not_found' }`) para código inexistente, vencido, cancelado, página pausada ou apagada,
# responsável que não pode mais atender e conta sem a flag: quem tenta adivinhar códigos não distingue um caso do
# outro. O payload leva só o primeiro nome e o telefone mascarado; nunca o número inteiro, e-mail ou id interno.
# Convite agendado leva também `starts_at` (no fuso da página) e `timezone` (IANA), para a tela "Você já agendou"
# dizer o dia e a hora.
#
# `viewed` registra a abertura depois do primeiro render (POST, para pré-visualização de link não contar) e ignora
# robôs de pré-visualização pelo `User-Agent`, comparado por `include?` numa lista fechada.
#
# Gestão da reunião (#1192, contrato F2-A): convite agendado mostra `meeting` e aceita `confirm`, `cancel`,
# `reschedule` e `stop_notices` (respondem o mesmo JSON do GET; recusa = 422 `{ error: <código> }`). O link de
# convite agendado continua abrindo até 1 dia depois do fim da reunião, inclusive cancelada (mostra "Cancelada") e
# inclusive com a página pausada (o cliente ainda precisa poder cancelar).
class Public::Api::V2::InvitesController < PublicController
  # Comparados em minúsculas. Só nomes de robôs: um `bot` solto casaria com celular de gente (ex.: CUBOT).
  ROBOT_AGENTS = %w[whatsapp facebookexternalhit facebot twitterbot slackbot telegrambot discordbot linkedinbot googlebot
                    bingbot preview crawler spider].freeze

  MANAGE_ERRORS = %w[not_changeable too_late slot_unavailable booking_failed].freeze

  before_action :set_invite

  rescue_from ::Crm::BookingV2::ManageError do |error|
    code = MANAGE_ERRORS.include?(error.message) ? error.message : 'booking_failed'
    render json: { error: code }, status: :unprocessable_entity
  end

  def show
    render_invite
  end

  def confirm
    manage.confirm!
    render_invite
  end

  def cancel
    manage.cancel!
    render_invite
  end

  def reschedule
    manage.reschedule!(starts_at: params[:starts_at], duration: params[:duration].presence)
    render_invite
  end

  def stop_notices
    manage.stop_notices!
    render_invite
  end

  def viewed
    record_view unless robot?
    head :no_content
  end

  private

  def set_invite
    @invite = ::Crm::BookingInvite.includes(:account, :contact, :booking_link, :meeting, booking_profile: :default_assignee)
                                  .find_by(code: params[:code].to_s)
    render json: { error: 'not_found' }, status: :not_found unless usable?
  end

  def usable?
    return false if @invite.blank? || !@invite.active?
    return false unless ::Crm::Config.booking_v2_enabled?(@invite.account)
    return @invite.meeting.present? if scheduled?

    ::Crm::BookingV2::InvitePages.new(@invite.account).invite_usable?(@invite)
  end

  def scheduled?
    @invite.scheduled_at.present?
  end

  def manage
    ::Crm::BookingV2::ManageMeeting.new(@invite)
  end

  def render_invite
    @invite.reload
    payload = {
      code: @invite.code, page_slug: page_slug, state: scheduled? ? 'scheduled' : 'open',
      contact_first_name: ::Crm::BookingV2::InviteText.first_name(@invite.contact).presence,
      phone_masked: ::Crm::BookingV2::PhoneMask.mask(@invite.contact.phone_number)
    }
    return render json: payload unless scheduled?

    render json: payload.merge(scheduled_time, meeting: ::Crm::BookingV2::ManagePayload.new(@invite).as_json,
                                               contact_whatsapp_url: ::Crm::BookingV2::PublicPageSerializer.whatsapp_url(@invite.booking_profile))
  end

  def page_slug
    @invite.booking_link&.slug || @invite.booking_profile.slug
  end

  def scheduled_time
    starts_at = @invite.meeting&.starts_at
    return {} if @invite.scheduled_at.blank? || starts_at.blank?

    zone = ActiveSupport::TimeZone[@invite.booking_profile.resolved_timezone]
    { starts_at: (zone ? starts_at.in_time_zone(zone) : starts_at.utc).iso8601, timezone: zone&.tzinfo&.name }
  end

  def robot?
    agent = request.user_agent.to_s.downcase
    ROBOT_AGENTS.any? { |name| agent.include?(name) }
  end

  # Uma instrução só: duas aberturas ao mesmo tempo somam as duas, e a primeira data nunca é sobrescrita.
  def record_view
    now = Time.current
    ::Crm::BookingInvite.where(id: @invite.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['open_count = open_count + 1, last_opened_at = ?, first_opened_at = COALESCE(first_opened_at, ?), updated_at = ?', now, now, now]
    )
  end
end
