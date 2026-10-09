# API pública da página de agendamento v2 (#1189, J2/RA-05). Sem login: o slug opaco (da página ou do link
# individual) é a única autorização; nunca há id de conta na URL e o Pundit não entra.
#
# 404 UNIFORME `{ error: 'not_found' }` para slug desconhecido, página antiga, flag da conta desligada e responsável
# que não pode mais atender. Página pausada: o GET responde só o aviso de pausa (com o WhatsApp da empresa, para
# não ser beco sem saída) e o resto responde 404. `?preview=<token>` mostra a página despublicada (GET e horários),
# mas nunca reserva.
#
# Envio de formulário (reserva e pedido de contato): honeypot `company` vazio, `form_token` emitido no GET para o
# MESMO slug com idade entre 2 s e 2 h, captcha quando a instalação tem `HCAPTCHA_SERVER_KEY`. Toda recusa de robô
# é o mesmo 422 `booking_failed`. Erros visíveis ao público formam um conjunto fechado (PUBLIC_ERRORS); o resto vira
# `booking_failed`, sem detalhe interno.
class Public::Api::V2::BookingController < PublicController
  PUBLIC_ERRORS = %w[slot_unavailable invalid_phone invalid_name invalid_email email_required too_many_open].freeze
  FORM_MIN_AGE = 2.seconds
  FORM_MAX_AGE = 2.hours

  before_action :set_page
  before_action :ensure_readable, only: [:slots, :next_slot]
  before_action :ensure_bookable, :ensure_human, only: [:create, :contact_request]

  rescue_from StandardError, with: :render_unexpected_error

  def show
    return render json: serializer.paused if @page.paused?
    return render_not_found unless @page.readable?

    render json: serializer.full
  end

  def slots
    date = parsed_date
    available = date ? ::Crm::BookingV2::Slots.new(profile: @page.profile, host: @page.host, date: date, duration: params[:duration]).perform : []
    render json: { date: date, slots: available }
  rescue ArgumentError
    render_booking_error('booking_failed')
  end

  def next_slot
    starts_at = ::Crm::BookingV2::Slots.next_slot(profile: @page.profile, host: @page.host, duration: params[:duration])
    render json: { starts_at: starts_at }
  rescue ArgumentError
    render_booking_error('booking_failed')
  end

  def create
    outcome = ::Crm::BookingV2::PublicBooking.new(page: @page, params: booking_params).perform
    render json: confirmation(outcome), status: outcome.existing ? :ok : :created
  rescue ArgumentError => e
    render_booking_error(e.message)
  end

  def contact_request
    ::Crm::BookingV2::ContactRequest.new(page: @page, name: params[:name], phone: params[:phone], consent: consent_params).perform
    render json: { requested: true }, status: :created
  rescue ArgumentError => e
    render_booking_error(e.message)
  end

  private

  def set_page
    @page = ::Crm::BookingV2::PublicPage.find(params[:slug], preview_token: params[:preview])
    render_not_found if @page.blank?
  end

  def ensure_readable
    render_not_found unless @page.readable?
  end

  def ensure_bookable
    render_not_found unless @page.bookable?
  end

  def ensure_human
    render_booking_error('booking_failed') unless params[:company].blank? && form_token_valid? && ChatwootCaptcha.new(params[:captcha_token]).valid?
  end

  def form_token_valid?
    payload = ::Crm::BookingV2::Tokens.verify('form', params[:form_token].to_s)
    return false unless payload.is_a?(Hash) && payload['s'] == @page.slug

    age = Time.current.to_i - payload['t'].to_i
    age.between?(FORM_MIN_AGE.to_i, FORM_MAX_AGE.to_i)
  end

  def serializer
    ::Crm::BookingV2::PublicPageSerializer.new(@page)
  end

  def parsed_date
    Date.iso8601(params[:date].to_s).iso8601
  rescue Date::Error
    nil
  end

  def booking_params
    params.permit(:name, :phone, :email, :starts_at, :duration, :location_type, :invite_code).to_h.merge(consent: consent_params)
  end

  def consent_params
    raw = params[:consent]
    raw.is_a?(ActionController::Parameters) ? raw.permit(:accepted, :text_key).to_h : {}
  end

  def confirmation(outcome)
    meeting = outcome.meeting
    {
      confirmed: true, starts_at: local_iso(meeting, meeting.starts_at), ends_at: local_iso(meeting, meeting.ends_at),
      timezone: meeting.timezone, location: confirmation_location(meeting), ics_url: ics_url(outcome.invite),
      manage_url: outcome.invite.url, contact_whatsapp_url: ::Crm::BookingV2::PublicPageSerializer.whatsapp_url(@page.profile)
    }
  end

  # Horário no fuso da página, como os horários livres.
  def local_iso(meeting, time)
    time.in_time_zone(ActiveSupport::TimeZone[meeting.timezone.to_s] || Time.zone).iso8601
  end

  def confirmation_location(meeting)
    location = meeting.metadata.to_h['location'].to_h
    { type: location['type'].presence || meeting.online_meeting_type, join_url: meeting.online_meeting_url.presence,
      address: location['address'].presence }.compact
  end

  def ics_url(invite)
    token = ::Crm::BookingV2::Tokens.generate('ics', { 'c' => invite.code }, expires_in: Public::Api::V2::IcsController::TOKEN_TTL)
    "#{::Crm::BookingInvite.base_url}/public/api/v2/ics/#{token}"
  end

  def render_booking_error(code)
    public_code = PUBLIC_ERRORS.include?(code) ? code : 'booking_failed'
    Rails.logger.info("Public booking v2 rejected: #{code}") if public_code != code
    render json: { error: public_code }, status: :unprocessable_entity
  end

  def render_not_found
    render json: { error: 'not_found' }, status: :not_found
  end

  def render_unexpected_error(error)
    Rails.logger.error("Public booking v2 error: #{error.class.name}")
    render_booking_error('booking_failed')
  end
end
