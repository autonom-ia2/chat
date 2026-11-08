class Api::V1::Accounts::Crm::FollowUpsController < Api::V1::Accounts::Crm::BaseController
  before_action :fetch_follow_up, only: [:show, :update, :destroy, :complete, :cancel, :dismiss_reminder, :reschedule]
  # Soma um `code` estável ao 422 genérico quando é o fallback de template (achado da revisão em #1349).
  rescue_from ActiveRecord::RecordInvalid do |exception|
    log_handled_error(exception)
    render json: Crm::FollowUps::RecordInvalidResponse.render(exception), status: :unprocessable_entity
  end
  # Quem recebe (#1462) fora da regra: código estável para a tela traduzir.
  rescue_from Crm::FollowUps::RecipientParams::Invalid do |exception|
    render json: { error: exception.message }, status: :unprocessable_entity
  end

  RESULTS_PER_PAGE = 50
  RECIPIENT_KEYS = %i[recipient_mode recipient_user_ids recipient_team_id].freeze
  RECURRENCE_PARAMS = [:frequency, :weekdays_only, :ends_mode, :ends_on, :occurrences_count, { weekdays: [] }].freeze
  MAX_RESULTS_PER_PAGE = 100

  def messaging_window
    authorize ::Crm::FollowUp, :index?
    return render json: { error: 'conversation_id_required' }, status: :unprocessable_entity if params[:conversation_id].blank?

    conversation = visible_conversation(params[:conversation_id])
    authorize_conversation!(conversation)
    render json: messaging_window_payload(conversation)
  end

  def index
    authorize ::Crm::FollowUp
    @follow_ups = filtered_follow_ups.order(:due_at, :id).page(params[:page] || 1).per(per_page)
    @follow_ups_count = filtered_follow_ups.count
  end

  def reminders
    authorize ::Crm::FollowUp, :index?
    @follow_ups = Crm::FollowUps::ReminderPopupQuery.new(
      account: Current.account,
      user: Current.user,
      account_user: Current.account_user
    ).perform
    @follow_ups_count = @follow_ups.size
    render :index
  end

  def show; end

  # card_id é opcional (#1461): sem ele, o lembrete fica só no calendário ou com um cliente (contact_id). Com
  # recurrence, nasce uma série e a primeira vez (#1460); recipient_* diz quem recebe (#1462).
  def create
    authorize ::Crm::FollowUp
    card = params_for_create[:card_id].present? ? visible_card(params_for_create[:card_id]) : nil
    ensure_card_funnel!(card) if card
    conversation = card ? resolved_conversation(card, params_for_create) : nil
    authorize_conversation!(conversation) if conversation.present?
    @follow_up = Crm::FollowUps::Creator.new(
      account: Current.account, user: Current.user, card: card, conversation: conversation, attributes: params_for_create
    ).perform
    after_follow_up_change('follow_up_created', @follow_up)
    render :show, status: :created
  rescue Crm::FollowUps::Creator::CardArchived
    render json: { message: I18n.t('crm.follow_ups.card_archived'), code: 'card_archived' }, status: :unprocessable_entity
  end

  def update
    attributes = params_for_update
    @follow_up.update!(attributes)
    Crm::FollowUps::SnoozeHandler.apply(@follow_up)
    after_follow_up_change('follow_up_updated', @follow_up)
    render :show
  end

  def destroy
    cancel
  end

  def complete
    transition_follow_up(:done, :completed_at, 'follow_up_completed')
  end

  def cancel
    transition_follow_up(:canceled, :canceled_at, 'follow_up_canceled')
  end

  def dismiss_reminder
    Crm::FollowUps::ReminderDismisser.new(follow_up: @follow_up, user: Current.user).perform
    render :show
  end

  # Intent-named reschedule (calendar drag / "Reschedule" action). Reuses the
  # service so the WhatsApp past-guard, snooze re-apply, card next-due recompute,
  # audit log, and broadcast all stay consistent with the create/update paths.
  def reschedule
    @follow_up = Crm::FollowUps::Rescheduler.new(
      follow_up: @follow_up,
      user: Current.user,
      due_at: params[:due_at],
      reminders_only: ActiveModel::Type::Boolean.new.cast(params[:reminders_only]) == true
    ).perform
    render :show
  rescue Crm::FollowUps::Rescheduler::PastDueError, Crm::FollowUps::Rescheduler::NotAReminderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_follow_up
    @follow_up = policy_scope(::Crm::FollowUp).includes(:card, :conversation, :contact, :inbox, :assignee, :created_by).find(params[:id])
    authorize @follow_up, "#{action_name}?".to_sym
  end

  def filtered_follow_ups
    ::Crm::FollowUps::FilterQuery.new(scope: policy_scope(::Crm::FollowUp), params: params).perform
  end

  def per_page
    params.fetch(:per_page, RESULTS_PER_PAGE).to_i.clamp(1, MAX_RESULTS_PER_PAGE)
  end

  def messaging_window_payload(conversation)
    at = (Time.zone.parse(params[:at].to_s) rescue nil) if params[:at].present? # rubocop:disable Style/RescueModifier
    window = Crm::FollowUps::MessagingWindow.new(conversation, at: at)
    inbox = conversation.inbox
    {
      whatsapp_capable: window.whatsapp_capable?,
      can_send_session_message: window.can_send_session_message?,
      requires_template: window.requires_template?,
      whatsapp_api_available: window.hybrid_web_available?,
      channel_type: inbox.channel_type,
      whatsapp_api_inbox: inbox.channel_type == 'Channel::Api' && inbox.channel.whatsapp_api_campaign_channel?,
      whatsapp_native_inbox: inbox.channel_type == 'Channel::Whatsapp',
      inbox_id: conversation.inbox_id
    }
  end

  def visible_card(card_id) = policy_scope(::Crm::Card).find(card_id)

  # Acesso por funil (#1148, decisão b): criar lembrete é mexer no card; exige o funil dele.
  def ensure_card_funnel!(card)
    guard = ::Crm::Access::CardGuard.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    raise Pundit::NotAuthorizedError unless guard.edit_allowed?(card)
  end

  def visible_conversation(conversation_id)
    Current.account.conversations.find(conversation_id)
  end

  def authorize_conversation!(conversation)
    Crm::Conversations::AccessAuthorizer.new(account: Current.account, user: Current.user,
                                             account_user: Current.account_user).authorize!(conversation)
  end

  def resolved_conversation(card, attributes)
    return visible_conversation(attributes[:conversation_id]) if attributes[:conversation_id].present?

    visible_primary_conversation(card)
  end

  def visible_primary_conversation(card)
    conversation = card.primary_conversation
    return if conversation.blank?

    authorize_conversation!(conversation)
    conversation
  rescue Pundit::NotAuthorizedError
    nil
  end

  def after_follow_up_change(event_type, follow_up)
    Crm::FollowUps::SnoozeHandler.apply(follow_up) if follow_up.pending?
    Crm::FollowUps::CardNextDueUpdater.update(follow_up.card)
    Crm::ActivityLogger.new(
      card: follow_up.card,
      actor: Current.user,
      event_type: event_type,
      conversation: follow_up.conversation,
      payload: activity_payload(follow_up)
    ).perform
    Crm::Cards::Broadcaster.broadcast(follow_up.card, Events::Types::CRM_CARD_UPDATED)
  end

  def activity_payload(follow_up)
    { follow_up_id: follow_up.id, title: follow_up.title, status: follow_up.status,
      automation_mode: follow_up.automation_mode, due_at: follow_up.due_at&.iso8601 }
  end

  def params_for_create
    follow_up_params
  end

  # Chaves que só o servidor escreve (transporte do Híbrido) nunca entram pelo metadata do cliente.
  # "Mudar só esta vez" (#1460) também troca quem recebe (#1462) desta vez.
  def params_for_update
    attributes = follow_up_params.except(:card_id, :conversation_id, :contact_id, :company_id, :recurrence)
    attributes = attributes.except(*RECIPIENT_KEYS).merge(recipient_changes(attributes))
    attributes[:metadata] &&= ::Crm::FollowUps::MetadataSanitizer.without_server_keys(attributes[:metadata])
    attributes
  end

  def recipient_changes(attributes)
    ::Crm::FollowUps::RecipientParams.new(account: Current.account, card: @follow_up.card, attributes: attributes,
                                          user: Current.user, account_user: Current.account_user).perform
  end

  def follow_up_params
    parameter_set(:follow_up).permit(
      :card_id, :conversation_id, :contact_id, :company_id, :title, :description, :follow_up_type,
      :automation_mode, :due_at, :timezone, :recipient_mode, :recipient_team_id,
      recipient_user_ids: [], metadata: {}, recurrence: RECURRENCE_PARAMS
    ).to_h.with_indifferent_access
  end

  def transition_follow_up(status, timestamp_field, event_type)
    return render :show unless @follow_up.pending? || @follow_up.overdue?

    updates = { status: status }
    updates[timestamp_field] = Time.current
    @follow_up.update!(updates)
    after_follow_up_change(event_type, @follow_up)
    render :show
  end
end
