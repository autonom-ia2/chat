class Whatsapp::EmbeddedSignupService
  # Meta's longest event name (FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING) has 39 characters.
  TRACE_VALUE_LIMIT = 64

  def initialize(account:, params:, inbox_id: nil)
    @account = account
    @code = params[:code]
    @waba_id = params[:waba_id]
    @phone_number_id = params[:phone_number_id]
    @inbox_id = inbox_id
    @is_coexistence = ActiveModel::Type::Boolean.new.cast(params[:is_coexistence])
    @signup_event = trace_value(params[:signup_event])
    @signup_version = trace_value(params[:signup_version])
  end

  def perform
    validate_parameters!

    access_token = exchange_code_for_token
    phone_info = fetch_phone_info(access_token)

    channel = create_or_reauthorize_channel(access_token, phone_info)
    record_signup_trace(channel)
    # NOTE: We call setup_webhooks explicitly here instead of relying on after_commit callback because:
    # 1. Reauthorization flow updates an existing channel (not a create), so after_commit on: :create won't trigger
    # 2. We need to run check_channel_health_and_prompt_reauth after webhook setup completes
    # 3. The channel is marked with source: 'embedded_signup' to skip the after_commit callback
    channel.setup_webhooks(is_coexistence: @is_coexistence)
    # Fire the Coexistence contacts + history sync immediately (Meta's 24h window starts now).
    # Best-effort: the service swallows its own errors so onboarding never fails because of it.
    # Gated at the call site (not just inside the service) so flag OFF means zero new code runs here.
    # Deliberately NOT gated on @is_coexistence (4.18.0): Meta allows one sync per onboarding inside a
    # 24h window, so a missing or misclassified client flag would lose the customer's history for good.
    # The service already limits itself to embedded-signup channels and to a single request.
    Whatsapp::HistorySyncService.new(channel).perform if Whatsapp::HistorySync.enabled?
    # Skip health check on reauth (avoids false disconnect emails) and on coexistence signups
    # (Meta's health data can lag several minutes behind a fresh FINISH event).
    check_channel_health_and_prompt_reauth(channel) if @inbox_id.blank? && !@is_coexistence
    log_signup_completed(channel)
    channel

  rescue StandardError => e
    Rails.logger.error("[WHATSAPP] Embedded signup failed: #{e.message}")
    raise e
  end

  private

  # #1315: keeps how Meta finished this signup (terminal event, payload version, coexistence)
  # on the channel. The container log is lost on every blue-green deploy, so the database is
  # the only durable record of which Embedded Signup version actually connected each number.
  # update_column on purpose: a save would re-run validate_provider_config (two Graph calls)
  # for keys that do not touch the credentials. Each signup overwrites the previous trace: the
  # stored token is the latest one, so the latest signup is what the trace must describe. An
  # empty event means none reached us: the reauthorize grace window ran out, or the browser
  # still ran a bundle from before #1315.
  def record_signup_trace(channel)
    trace = {
      'signup_event' => @signup_event,
      'signup_version' => @signup_version,
      'signup_is_coexistence' => @is_coexistence,
      'signup_completed_at' => Time.current.iso8601
    }
    # rubocop:disable Rails/SkipsModelValidations
    channel.update_column(:provider_config, channel.provider_config.merge(trace))
    # rubocop:enable Rails/SkipsModelValidations
  rescue StandardError => e
    # The trace is evidence, not part of the connection: the channel and its token are already
    # saved, so failing here must not turn a working signup into an error for the customer.
    # Class only: the message of a failed write on provider_config is not needed here and could echo its values.
    Rails.logger.error("[WHATSAPP] Embedded signup trace not recorded channel_id=#{channel.id} error_class=#{e.class}")
  end

  def log_signup_completed(channel)
    Rails.logger.info(
      "[WHATSAPP] Embedded signup completed account_id=#{@account.id} channel_id=#{channel.id} " \
      "reauthorization=#{@inbox_id.present?} event=#{@signup_event.presence || 'none'} " \
      "version=#{@signup_version.presence || 'none'} coexistence=#{@is_coexistence.inspect}"
    )
  end

  # Client-sent values go to the log and the database: keep only the characters Meta uses
  # in event names and versions, bounded, so a crafted value cannot forge log lines.
  def trace_value(value)
    value.to_s.delete('^A-Za-z0-9_.').first(TRACE_VALUE_LIMIT)
  end

  def exchange_code_for_token
    Whatsapp::TokenExchangeService.new(@code).perform
  end

  def fetch_phone_info(access_token)
    Whatsapp::PhoneInfoService.new(
      @waba_id, @phone_number_id, access_token, expected_phone_number: reauthorizing_channel&.phone_number
    ).perform
  end

  # When phone_number_id is omitted (coexistence completions can leave it blank), this lets
  # PhoneInfoService match the WABA number against the channel being reauthorized instead of
  # arbitrarily taking the first number, which would misidentify a WABA with multiple numbers.
  def reauthorizing_channel
    return nil if @inbox_id.blank?

    @reauthorizing_channel ||= @account.inboxes.find(@inbox_id).channel
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def create_or_reauthorize_channel(access_token, phone_info)
    if @inbox_id.present?
      Whatsapp::ReauthorizationService.new(
        account: @account,
        inbox_id: @inbox_id,
        phone_number_id: @phone_number_id,
        waba_id: @waba_id
      ).perform(access_token, phone_info)
    else
      waba_info = { waba_id: @waba_id, business_name: phone_info[:business_name] }
      Whatsapp::ChannelCreationService.new(@account, waba_info, phone_info, access_token).perform
    end
  end

  def check_channel_health_and_prompt_reauth(channel)
    health_data = Whatsapp::HealthService.new(channel).fetch_health_status
    return unless health_data

    if channel_in_pending_state?(health_data)
      channel.prompt_reauthorization!
    else
      Rails.logger.info "[WHATSAPP] Channel #{channel.phone_number} health check passed"
    end
  rescue StandardError => e
    Rails.logger.error "[WHATSAPP] Health check failed for channel #{channel.phone_number}: #{e.message}"
  end

  def channel_in_pending_state?(health_data)
    health_data[:platform_type] == 'NOT_APPLICABLE' ||
      health_data.dig(:throughput, 'level') == 'NOT_APPLICABLE'
  end

  def validate_parameters!
    missing_params = []
    missing_params << 'code' if @code.blank?
    missing_params << 'waba_id' if @waba_id.blank?

    return if missing_params.empty?

    raise ArgumentError, "Required parameters are missing: #{missing_params.join(', ')}"
  end
end
