class Crm::FollowUps::ReminderNotifier
  include Rails.application.routes.url_helpers

  REMINDER_MODES = Crm::FollowUps::Broadcaster::REMINDER_MODES

  def initialize(follow_up)
    @follow_up = follow_up
  end

  def perform
    return unless ::Crm::Config.enabled?
    return unless REMINDER_MODES.include?(@follow_up.automation_mode)
    return unless @follow_up.overdue?

    recipient_users.each { |user| notify_user(user) }
  end

  private

  # Quem recebe (#1462) e o acesso por funil (#1148, parte C): o mesmo RecipientResolver do Broadcaster.
  def recipient_users
    Crm::FollowUps::RecipientResolver.new(@follow_up).users
  end

  def notify_user(user)
    setting = user.notification_settings.find_by(account_id: @follow_up.account_id)
    return if setting.blank?

    send_push(user) if setting.push_crm_followup_reminder?
    send_email(user) if setting.email_crm_followup_reminder?
  end

  # ---- push (reuse VapidService + WebPush + cleanup pattern) ----
  def send_push(user)
    return unless VapidService.public_key
    # VAPID subject must be a valid https URL; bail if FRONTEND_URL is unset.
    return if ENV.fetch('FRONTEND_URL', '').blank?

    user.notification_subscriptions.where(subscription_type: :browser_push).find_each do |subscription|
      send_browser_push(user, subscription)
    end
  end

  def send_browser_push(user, subscription)
    WebPush.payload_send(**browser_push_payload(subscription))
  rescue WebPush::ExpiredSubscription, WebPush::InvalidSubscription, WebPush::Unauthorized => e
    Rails.logger.info "WebPush subscription expired: #{e.message}"
    subscription.destroy!
  rescue WebPush::TooManyRequests => e
    Rails.logger.warn "WebPush rate limited for #{user.email} on account #{@follow_up.account_id}: #{e.message}"
  rescue Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout, Socket::ResolutionError => e
    Rails.logger.error "WebPush operation error: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @follow_up.account).capture_exception
  end

  def browser_push_payload(subscription)
    {
      message: JSON.generate(push_message),
      endpoint: subscription.subscription_attributes['endpoint'],
      p256dh: subscription.subscription_attributes['p256dh'],
      auth: subscription.subscription_attributes['auth'],
      vapid: {
        subject: crm_url,
        public_key: VapidService.public_key,
        private_key: VapidService.private_key
      },
      ssl_timeout: 5, open_timeout: 5, read_timeout: 5
    }
  end

  def push_message
    message = {
      title: push_title,
      tag: "crm_followup_reminder_#{@follow_up.id}",
      url: crm_url
    }

    return message unless meeting_reminder?

    message.merge(meeting_payload)
  end

  def crm_url
    "#{ENV.fetch('FRONTEND_URL', '')}/app/accounts/#{@follow_up.account_id}/crm"
  end

  def push_title
    return I18n.t('crm.follow_up_reminder.push_title', title: @follow_up.title) unless meeting_reminder?

    I18n.t(
      'crm.meetings.reminder.push_title',
      title: meeting.title,
      time: localized_meeting_time(:short),
      default: 'Lembrete de reunião: %{title} às %{time}'
    )
  end

  def meeting_payload
    {
      follow_up_id: @follow_up.id,
      due_at: @follow_up.due_at&.iso8601,
      card_id: @follow_up.card_id,
      meeting_id: meeting.id,
      meeting_title: meeting.title,
      meeting_starts_at: meeting_starts_at.iso8601,
      meeting_timezone: meeting.timezone,
      online_meeting_url: meeting.online_meeting_url,
      online_meeting_type: meeting.online_meeting_type,
      join_url: meeting.online_meeting_url,
      cta_label: I18n.t('crm.meetings.reminder.join_cta', default: 'Entrar na reunião'),
      cta_url: meeting.online_meeting_url
    }
  end

  def meeting_reminder?
    @follow_up.follow_up_type.to_sym == :meeting && meeting.present?
  end

  def meeting
    return @meeting if defined?(@meeting)

    @meeting = follow_up_meeting || reminder_meeting
  end

  def follow_up_meeting
    return unless @follow_up.respond_to?(:meeting)

    @follow_up.meeting
  end

  def reminder_meeting
    return unless defined?(Crm::Meeting)
    return unless Crm::Meeting.table_exists? && Crm::Meeting.column_names.include?('reminder_id')

    Crm::Meeting.find_by(
      account_id: @follow_up.account_id,
      card_id: @follow_up.card_id,
      reminder_id: @follow_up.id
    )
  end

  def meeting_starts_at
    meeting.starts_at.in_time_zone(meeting.timezone)
  end

  def localized_meeting_time(format)
    I18n.l(meeting_starts_at, format: format)
  rescue I18n::MissingTranslationData
    I18n.l(meeting_starts_at, format: :long)
  end

  # ---- email (mirror EmailNotificationService guards) ----
  def send_email(user)
    return if user.email.blank?
    return if user.confirmed_at.nil?
    return unless @follow_up.account.within_email_rate_limit?

    Crm::FollowUpReminderMailer.with(account: @follow_up.account)
                               .reminder(@follow_up, user)
                               .deliver_later
    @follow_up.account.increment_email_sent_count
  end
end
