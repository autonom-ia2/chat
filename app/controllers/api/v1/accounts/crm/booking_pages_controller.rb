# Páginas de agendamento novas (page_version 2, #1187 F1-A): criar a partir de modelo, editar, publicar, pausar,
# prévia, marca e quem atende. Fica atrás da flag da conta (`crm_booking_v2`, 404 desligada), do módulo de função
# `agendamento` (ler = _view, escrever = _manage) e da `Crm::BookingPagePolicy`. Só enxerga páginas v2 da conta.
#
# Não toca canal de e-mail nem lista membros de caixa (J8-A5). A gaveta antiga (BookingProfilesController) segue
# só do administrador e só com páginas v1.
class Api::V1::Accounts::Crm::BookingPagesController < Api::V1::Accounts::Crm::BaseController
  PREVIEW_TTL = 1.hour

  # A mensagem é o código devolvido (caixa de agenda ou de avisos fora do que a pessoa pode escolher).
  class InvalidInbox < StandardError; end

  before_action :ensure_booking_v2_enabled
  before_action -> { check_module_permission!('agendamento') }
  before_action :fetch_page, except: [:index, :create]
  before_action :authorize_page

  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: error.record.errors.full_messages.first || 'Invalid booking page', errors: error.record.errors.to_hash },
           status: :unprocessable_entity
  end

  def index
    report = ::Crm::BookingV2::AttentionReport.new(account: Current.account)
    pages = pages_scope.includes(:default_assignee, agent_booking_links: :agent).order(:id).to_a
    counts = ::Crm::BookingV2::AttentionReport.upcoming_counts(pages)
    payload = pages.map { |page| page_summary(page, report, counts) }
    render json: { payload: payload }
  end

  def show
    render_page
  end

  def create
    attributes = ::Crm::BookingV2::PageTemplates.attributes_for(params[:template_key].to_s, locale: account_locale)
    attributes[:title] = params[:title] if params[:title].present?
    @page = Current.account.crm_agent_booking_profiles.create!(attributes.merge(new_page_defaults))
    render_page(status: :created)
  rescue ::Crm::BookingV2::PageTemplates::UnknownTemplate
    render_unprocessable('crm.booking_v2.unknown_template')
  end

  def update
    @page.update!(page_params.merge(calendar_inbox_attributes).merge(notice_inbox_attributes))
    render_page
  rescue InvalidInbox => e
    render_unprocessable(e.message)
  end

  # "Testar no meu WhatsApp" (#1192, J3-A11): manda ao número informado, pela caixa de avisos, um link igual ao do
  # cliente. O convite de teste fica marcado (`metadata.test`) e fora dos números.
  def test_invite
    ::Crm::BookingV2::TestInvite.new(page: @page, user: Current.user, phone: params[:phone]).perform
    render json: { sent: true }
  rescue ::Crm::BookingV2::TestInvite::Refused => e
    render json: { error: e.message, reason: e.reason }.compact, status: :unprocessable_entity
  end

  def publish
    missing = publish_blockers(@page)
    return render json: { error: 'crm.booking_v2.publish_incomplete', missing: missing }, status: :unprocessable_entity if missing.any?

    @page.update!(enabled: true)
    render_page
  end

  def pause
    @page.update!(enabled: false)
    render_page
  end

  def destroy
    upcoming = ::Crm::BookingV2::AttentionReport.upcoming_meetings(@page).count
    return render json: { error: 'crm.booking_v2.has_upcoming_meetings', upcoming_meetings_count: upcoming }, status: :conflict if upcoming.positive?

    @page.destroy!
    head :no_content
  end

  def preview_token
    expires_at = PREVIEW_TTL.from_now
    token = ::Crm::BookingV2::Tokens.generate('preview', { 'p' => @page.id }, expires_in: PREVIEW_TTL)
    render json: { payload: { token: token, expires_at: expires_at.iso8601 } }
  end

  def logo
    upload(:logo)
  end

  def photo
    upload(:photo)
  end

  def people
    people = ::Crm::BookingV2::PagePeople.eligible(Current.account)
    render json: { payload: people.map { |user| ::Crm::BookingV2::PageSerializer.person(user) } }
  end

  def update_people
    ::Crm::BookingV2::PagePeople.new(@page).assign!(params[:user_ids])
    render_page
  rescue ::Crm::BookingV2::PagePeople::InvalidPeople
    render_unprocessable('crm.booking_v2.people_invalid')
  end

  private

  def ensure_booking_v2_enabled
    render json: { error: 'crm.booking_v2.disabled' }, status: :not_found unless ::Crm::Config.booking_v2_enabled?(Current.account)
  end

  def pages_scope
    policy_scope(::Crm::AgentBookingProfile, policy_scope_class: ::Crm::BookingPagePolicy::Scope)
  end

  def fetch_page
    @page = pages_scope.find(params[:id])
  end

  def authorize_page
    authorize(@page || ::Crm::AgentBookingProfile, "#{action_name}?", policy_class: ::Crm::BookingPagePolicy)
  end

  def render_page(status: :ok)
    attention = ::Crm::BookingV2::AttentionReport.new(account: Current.account).attention?(@page)
    payload = ::Crm::BookingV2::PageSerializer.new(@page.reload, attention: attention).full
    payload = payload.merge(calendar_options: calendar_inbox_options, notice_inbox_options: notice_inboxes.as_json)
    render json: { payload: payload }, status: status
  end

  def new_page_defaults
    pipeline = Current.account.crm_pipelines.active.order(:position, :id).first
    {
      page_version: ::Crm::AgentBookingProfile::NEW_PAGE, enabled: false, assignment_mode: :fixed,
      default_assignee: eligible?(Current.user) ? Current.user : nil,
      default_pipeline: pipeline, default_stage: pipeline&.stages&.order(:position, :id)&.first,
      timezone: ::Crm::Timezone::Resolver.new(account: Current.account).name_or_default
    }
  end

  # O cartão da lista. `missing` só para página desligada: com algo faltando, a tela mostra Rascunho.
  def page_summary(page, report, counts)
    serializer = ::Crm::BookingV2::PageSerializer.new(page, attention: report.attention?(page), upcoming_meetings_count: counts.fetch(page.id, 0))
    serializer.summary.merge(missing: page.enabled? ? [] : publish_blockers(page))
  end

  # O que impede publicar (publish e, para o Rascunho, a lista).
  def publish_blockers(page)
    missing = []
    missing << 'host' unless page_host_eligible?(page)
    missing << 'location' if Array(page.locations).empty?
    missing << 'working_hours' if page.weekdays.empty?
    missing << 'pipeline' unless pipeline_resolvable?(page)
    missing
  end

  # A reserva cria um card: sem funil e etapa resolvíveis o Booker recusa toda reserva, então não publica.
  def pipeline_resolvable?(page)
    ::Crm::BookingV2::Booker.pipeline_target(page).values.all?(&:present?)
  end

  def page_host_eligible?(page)
    return eligible?(page.default_assignee) if page.assignment_mode_fixed?

    page.agent_booking_links.select(&:enabled?).any? { |link| eligible?(link.agent) }
  end

  def eligible?(user)
    ::Crm::BookingV2::HostEligibility.eligible?(account: Current.account, user: user)
  end

  def upload(name)
    file = params[:file]
    return render_unprocessable('crm.booking_v2.file_missing') unless file.is_a?(ActionDispatch::Http::UploadedFile)

    @page.public_send(:"#{name}=", file)
    @page.save!
    render_page
  end

  # Meet/Teams pedem uma caixa Google/Microsoft com agenda JÁ conectada. Escolher uma delas não é conectar caixa
  # (J8-A5): a lista vem do escopo de caixas que a própria pessoa já enxerga.
  def calendar_inboxes
    policy_scope(::Inbox).includes(:channel).select do |inbox|
      channel = inbox.channel
      channel.is_a?(::Channel::Email) && channel.calendar_enabled? && (channel.google? || channel.microsoft?)
    end
  end

  def calendar_inbox_options
    calendar_inboxes.map { |inbox| { id: inbox.id, name: inbox.name, provider: inbox.channel.google? ? 'google' : 'microsoft' } }
  end

  def calendar_inbox_attributes
    body = params[:booking_page]
    return {} unless body.respond_to?(:key?) && body.key?(:calendar_inbox_id)

    raw = body[:calendar_inbox_id]
    return { inbox_id: nil } if raw.blank?

    inbox = calendar_inboxes.find { |item| item.id == raw.to_i }
    raise InvalidInbox, 'crm.booking_v2.calendar_inbox_invalid' if inbox.blank?

    { inbox_id: inbox.id }
  end

  # Caixas que podem mandar avisos (#1192), do escopo de caixas que a própria pessoa já enxerga.
  def notice_inboxes
    @notice_inboxes ||= ::Crm::BookingV2::NoticeInboxOptions.new(policy_scope(::Inbox))
  end

  def notice_inbox_attributes
    body = params[:booking_page]
    return {} unless body.respond_to?(:key?) && body.key?(:notice_inbox_id)
    return { notice_inbox_id: nil } if body[:notice_inbox_id].blank?

    inbox = notice_inboxes.find(body[:notice_inbox_id]) || (raise InvalidInbox, 'crm.booking_v2.notice_inbox_invalid')
    { notice_inbox_id: inbox.id }
  end

  def account_locale
    Current.account.locale.presence || I18n.default_locale
  end

  def page_params
    parameter_set(:booking_page).permit(
      :title, :description, :duration_minutes, :buffer_minutes, :booking_window_days, :min_notice_minutes,
      :timezone, :contact_phone, :default_pipeline_id, :default_stage_id, :invite_text, :invite_ttl_days, :notice_preset, :cancel_until_minutes,
      slot_durations: [], working_hours: [:start_hour, :end_hour, { weekdays: [] }],
      locations: [:type, :url, :address, :label], brand: [:color, :headline],
      notice_templates: ::Crm::MeetingNotice::KINDS.index_with { %i[name language id] }
    ).to_h
  end
end
