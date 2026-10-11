# Marcar pela agenda no painel (#1265): a janela "Agendar reunião" do card escolhe uma página publicada, vê os
# horários livres pela regra da página pública e marca pelo `Crm::BookingV2::Booker` (via `PanelBooking`).
#
# Atrás da flag da conta (`crm_booking_v2`, 404 desligada) e da `Crm::BookingPageMeetingPolicy` (quem pode atender
# pelo agendamento). Só páginas novas publicadas e com alguém para atender (`InvitePages#usable`); outra página é 404.
#
# - `GET bookable`: as páginas que servem, com durações, locais e se têm avisos no WhatsApp.
# - `GET :id/slots?date=&duration=`: horários livres do dia, no fuso da página; sem nenhum, o próximo livre.
# - `POST :id/meetings` (`card_id` ou `contact_id`, `starts_at`, `duration`, `location`, `notify`, `request_id`):
#   marca e devolve a reunião. Horário tomado = 409 `slot_unavailable`; outra recusa = 422 `crm.booking_v2.<código>`.
class Api::V1::Accounts::Crm::BookingPageMeetingsController < Api::V1::Accounts::Crm::BaseController
  REFUSALS = %w[
    slot_unavailable no_contact card_closed booking_failed invalid_name invalid_phone invalid_email invalid_starts_at
    invalid_duration invalid_location host_unavailable email_required calendar_unavailable availability_unavailable
    too_many_open no_pipeline_configured no_stage_configured
  ].freeze

  before_action :ensure_booking_v2_enabled
  before_action :authorize_booking
  before_action :fetch_page, except: [:index]

  def index
    render json: { payload: invite_pages.usable.map { |page| page_payload(page) } }
  end

  def slots
    host = invite_pages.link_for(@page, Current.user)&.agent || @page.default_assignee
    available = ::Crm::BookingV2::Slots.new(profile: @page, host: host, date: params[:date].to_s, duration: params[:duration].presence).perform
    next_slot = available.empty? ? ::Crm::BookingV2::Slots.next_slot(profile: @page, host: host, duration: params[:duration].presence) : nil
    render json: { payload: { date: params[:date].to_s, slots: available, next_slot: next_slot } }
  rescue ArgumentError => e
    render_refusal(e)
  end

  def create
    outcome = ::Crm::BookingV2::PanelBooking.new(page: @page, user: Current.user, client: client, params: booking_params).perform
    render json: { payload: meeting_payload(outcome) }, status: outcome.existing ? :ok : :created
  rescue ArgumentError => e
    render_refusal(e)
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def authorize_booking
    authorize(::Crm::AgentBookingProfile, "#{action_name}?", policy_class: ::Crm::BookingPageMeetingPolicy)
  end

  def invite_pages
    @invite_pages ||= ::Crm::BookingV2::InvitePages.new(Current.account)
  end

  def fetch_page
    @page = invite_pages.usable.find { |page| page.id == params[:id].to_i }
    render json: { error: 'crm.booking_v2.no_page' }, status: :not_found if @page.blank?
  end

  # O card pede edição (a reunião entra nele), como no MeetingsController#create. Só o contato: vê-lo e editar o card
  # aberto dele no funil da página (o mesmo que o Booker usaria), ou, sem card, poder criar um.
  def client
    if params[:card_id].present?
      card = Current.account.crm_cards.find(params[:card_id])
      authorize card, :update?
      return { card: card }
    end

    contact = Current.account.contacts.find(params[:contact_id])
    authorize contact, :show?
    card = open_card_of(contact)
    card ? authorize(card, :update?) : authorize(::Crm::Card, :create?)
    { contact: contact, card: card }
  end

  def open_card_of(contact)
    pipeline_id = ::Crm::BookingV2::Booker.pipeline_target(@page)[:pipeline_id]
    Current.account.crm_cards.active.where(contact_id: contact.id, pipeline_id: pipeline_id).order(updated_at: :desc).first
  end

  def booking_params
    params.permit(:starts_at, :duration, :location, :notify, :request_id).to_h
  end

  def page_payload(page)
    {
      id: page.id, title: page.title, timezone: page.resolved_timezone, duration_minutes: page.duration_minutes,
      durations: page.durations, notices: page.notices_usable?,
      locations: Array(page.locations).select { |item| item.is_a?(Hash) }.map { |item| location_payload(item) }
    }
  end

  def location_payload(location)
    {
      type: location['type'], label: ::Crm::BookingV2::LocationLabel.for(location, account: Current.account),
      needs_email: ::Crm::BookingPageSettings::CALENDAR_LOCATIONS.key?(location['type'].to_s)
    }
  end

  def meeting_payload(outcome)
    meeting = outcome.meeting
    {
      id: meeting.id, card_id: meeting.card_id, title: meeting.title, starts_at: meeting.starts_at.iso8601,
      ends_at: meeting.ends_at.iso8601, timezone: meeting.timezone, source: meeting.source,
      location: meeting.metadata.to_h['location'], manage_url: outcome.invite&.url, notice_will_send: outcome.notice_will_send
    }
  end

  # Código conhecido é recusa; outro ArgumentError é falha nossa: rastreador e 500, sem a mensagem.
  def render_refusal(error)
    unless REFUSALS.include?(error.message)
      ChatwootExceptionTracker.new(error, account: Current.account).capture_exception
      return render json: { error: 'crm.booking_v2.unavailable' }, status: :internal_server_error
    end

    status = error.message == 'slot_unavailable' ? :conflict : :unprocessable_entity
    render json: { error: "crm.booking_v2.#{error.message}" }, status: status
  end
end
