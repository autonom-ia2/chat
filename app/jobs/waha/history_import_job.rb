require 'timeout'

class Waha::HistoryImportJob < MutexApplicationJob
  # Older workers in a blue-green rollout must never consume this new job class.
  queue_as :waha_history

  LOCK_TIMEOUT = 10.minutes
  PAGE_SIZE = 10
  MAX_CONNECTION_WAIT = 24.hours
  CONNECTION_RETRY_WAIT = 1.minute
  POST_CONNECTION_WAIT = 15.minutes
  NEXT_PAGE_WAIT = 2.seconds
  PAGE_TIMEOUT = 8.minutes
  RECONCILIATION_WAIT = [5.minutes, 1.hour, 24.hours].freeze
  WORKING_STATUS = 'WORKING'.freeze
  FAILED_STATUS = 'FAILED'.freeze
  STATUS_VALUES = %w[waiting_connection running completed failed].freeze
  CHAT_ID_SUFFIXES = %w[@c.us @s.whatsapp.net @lid].freeze
  INTEGER_STATE_KEYS = %w[started_at before chats_offset messages_offset pass imported unavailable_media].freeze
  REQUIRED_STATE_KEYS = %w[
    started_at before status chats_offset messages_offset chat_id pass imported unavailable_media
  ].freeze

  class InvalidStateError < StandardError; end
  class InvalidResponseError < StandardError; end
  class IdentityMismatchError < StandardError; end
  class ConnectionFailedError < StandardError; end
  class PageTimeoutError < StandardError; end
  class ConnectorCapabilityError < StandardError; end
  Context = Struct.new(:inbox_id, :inbox, :channel, :client, :session, :state, keyword_init: true)

  retry_on Waha::Client::Error, wait: 60.seconds, attempts: 5 do |job, error|
    job.send(:fail_after_client_retries, job.arguments.first, error.class)
  end

  def perform(inbox_id)
    return unless context_for(inbox_id)

    with_lock("waha:history:#{inbox_id}", LOCK_TIMEOUT) do
      process_locked(inbox_id)
    end
  end

  private

  def process_locked(inbox_id)
    context = context_for(inbox_id)
    return unless context

    begin
      return unless prepare_context(context)

      Timeout.timeout(PAGE_TIMEOUT, PageTimeoutError) { process_page(context) }
    rescue MutexApplicationJob::LockAcquisitionError
      raise
    rescue Waha::Client::Error => e
      log_error(inbox_id, e.class)
      raise sanitized_client_error(e), cause: nil
    rescue StandardError => e
      mark_failed(context.channel, context.state, e.class)
      log_error(inbox_id, e.class)
    end
  end

  def context_for(inbox_id)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox

    channel = inbox.channel
    return unless eligible_channel?(channel)

    state = history_state(channel)
    return unless state && state['status'].to_s.in?(%w[completed failed]) == false

    Context.new(inbox_id: inbox_id, inbox: inbox, channel: channel, state: state)
  end

  def eligible_channel?(channel)
    channel.is_a?(Channel::Api) && channel.additional_attributes.to_h['provider'] == 'waha'
  end

  def history_state(channel)
    marker = channel.additional_attributes.to_h['waha_history_import']
    return unless marker.is_a?(Hash)

    marker.deep_stringify_keys
  end

  def validate_state!(state)
    raise InvalidStateError, 'state_keys_missing' unless (REQUIRED_STATE_KEYS - state.keys).empty?
    raise InvalidStateError, 'status_invalid' unless STATUS_VALUES.include?(state['status'])

    validate_integer_state!(state)
    validate_cutoff!(state)
    raise InvalidStateError, 'chat_id_invalid' unless state['chat_id'].nil? || state['chat_id'].is_a?(String)
  end

  def validate_integer_state!(state)
    valid = INTEGER_STATE_KEYS.all? { |key| state[key].is_a?(Integer) && state[key] >= 0 }
    raise InvalidStateError, 'state_integer_invalid' unless valid
  end

  def validate_cutoff!(state)
    now = Time.current.to_i
    raise InvalidStateError, 'started_at_invalid' unless state['started_at'].positive? && state['started_at'] <= now

    return validate_waiting_cursor!(state) if state['before'].zero?

    raise InvalidStateError, 'cutoff_invalid' unless state['before'].between?(state['started_at'], now)
  end

  def validate_waiting_cursor!(state)
    empty_cursor = state.values_at(*INTEGER_STATE_KEYS.drop(2)).all?(&:zero?) && state['chat_id'].nil?
    raise InvalidStateError, 'unfixed_cutoff_invalid' unless state['status'] == 'waiting_connection' && empty_cursor
  end

  def prepare_context(context)
    validate_state!(context.state)
    context.session = context.channel.additional_attributes.to_h['session'].to_s
    raise InvalidStateError, 'session_missing' if context.session.blank?

    context.client = Waha::Client.new
    return false unless ensure_working_connection!(context)

    begin_import!(context)
    true
  end

  def begin_import!(context)
    raise ConnectorCapabilityError, 'history_source_ids_unavailable' unless context.client.history_source_ids_available?

    validate_identity!(context.channel, context.client)
    context.state['before'] = Time.current.to_i if context.state['before'].zero?
    context.state['status'] = 'running'
    context.state.delete('error_class')
    persist_state(context.channel, context.state)
  end

  def ensure_working_connection!(context)
    current_session = context.client.get_session(context.session)
    return true if current_session.is_a?(Hash) && current_session['status'] == WORKING_STATUS

    if current_session.is_a?(Hash) && current_session['status'] == FAILED_STATUS
      mark_failed(context.channel, context.state, ConnectionFailedError)
      log_error(context.inbox_id, ConnectionFailedError)
      return false
    end

    context.state['status'] = 'waiting_connection'
    persist_state(context.channel, context.state)
    wait = connection_expired?(context.state) ? POST_CONNECTION_WAIT : CONNECTION_RETRY_WAIT
    self.class.set(wait: wait).perform_later(context.inbox_id)
    false
  end

  def connection_expired?(state)
    Time.current.to_i - state['started_at'] >= MAX_CONNECTION_WAIT.to_i
  end

  def validate_identity!(channel, client)
    plan = Waha::ExistingInboxMigrationPlanner.new(client: client).build(channel)
    return if plan && plan.changes.to_a.empty?

    raise IdentityMismatchError, 'remote_identity_or_configuration_changed'
  end

  def process_page(context)
    PageProcessor.new(context: context, persist_state: method(:persist_state)).call
  end

  def sanitized_client_error(error)
    status = error.status if error.status.is_a?(Integer)
    sanitized = Waha::Client::Error.new("waha_client_error status=#{status || 'unknown'}", status: status)
    sanitized.set_backtrace([])
    sanitized
  end

  def persist_state(channel, state)
    channel.with_lock do
      attrs = channel.additional_attributes.to_h
      current = attrs['waha_history_import']
      next if current.is_a?(Hash) && current['status'] == 'completed'

      attrs['waha_history_import'] = state.deep_stringify_keys
      channel.update_columns(additional_attributes: attrs) # rubocop:disable Rails/SkipsModelValidations
    end
    channel.reload
  end

  def mark_failed(channel, state, error_class)
    return unless channel && state

    state['status'] = 'failed'
    state['error_class'] = error_class.name
    persist_state(channel, state)
  end

  def fail_after_client_retries(inbox_id, error_class)
    inbox = Inbox.find_by(id: inbox_id)
    return unless inbox

    channel = inbox.channel
    return unless eligible_channel?(channel)

    state = history_state(channel)
    return unless state && !state['status'].in?(%w[completed failed])

    mark_failed(channel, state, error_class)
    log_error(inbox_id, error_class)
  end

  def log_error(inbox_id, error_class)
    Rails.logger.error("[Waha::HistoryImportJob] inbox=#{inbox_id} error=#{error_class}")
  end
end

Waha::HistoryImportJob::PageProcessor = Struct.new(:context, :persist_state, keyword_init: true) do
  def call
    return select_chat_page if state['chat_id'].blank?

    import_messages
  end

  private

  def state
    context.state
  end

  def select_chat_page
    chats = context.client.list_chats(
      context.session, limit: Waha::HistoryImportJob::PAGE_SIZE, offset: state['chats_offset']
    )
    raise Waha::HistoryImportJob::InvalidResponseError, 'chats_not_an_array' unless chats.is_a?(Array)
    return finish_or_reconcile if chats.empty?

    choose_chat(chats)
  end

  def choose_chat(chats)
    index, chat_id = select_chat(chats)
    return advance_invalid_chats(chats) if chat_id.nil? && chats.length == Waha::HistoryImportJob::PAGE_SIZE
    return finish_or_reconcile if chat_id.nil?

    state['chats_offset'] += index
    state['chat_id'] = chat_id
    persist_state.call(context.channel, state)
    import_messages
  end

  def select_chat(chats)
    chats.each_with_index do |chat, index|
      chat_id = chat['id'] if chat.is_a?(Hash)
      return [index, chat_id] if valid_chat_id?(chat_id)
    end

    [nil, nil]
  end

  def valid_chat_id?(chat_id)
    chat_id.is_a?(String) && chat_id.end_with?(*Waha::HistoryImportJob::CHAT_ID_SUFFIXES)
  end

  def advance_invalid_chats(chats)
    state['chats_offset'] += chats.length
    persist_state.call(context.channel, state)
    schedule(Waha::HistoryImportJob::NEXT_PAGE_WAIT)
  end

  def import_messages
    chat_id = state['chat_id']
    raise Waha::HistoryImportJob::InvalidStateError, 'chat_id_invalid' unless valid_chat_id?(chat_id)

    messages = context.client.list_messages(
      context.session,
      chat_id: chat_id,
      limit: Waha::HistoryImportJob::PAGE_SIZE,
      offset: state['messages_offset'],
      before: state['before']
    )
    raise Waha::HistoryImportJob::InvalidResponseError, 'messages_not_an_array' unless messages.is_a?(Array)

    result = Waha::HistoryImporter.new(
      inbox: context.inbox,
      client: context.client,
      before: state['before']
    ).import(chat_id: chat_id, messages: messages)
    update_message_state(messages, result)
  end

  def update_message_state(messages, result)
    error = Waha::HistoryImportJob::InvalidResponseError
    raise error, 'import_result_not_a_hash' unless result.is_a?(Hash)

    state['imported'] += import_count(result, :imported)
    state['unavailable_media'] += import_count(result, :unavailable_media)
    advance_message_state(messages)
    persist_state.call(context.channel, state)
    schedule(Waha::HistoryImportJob::NEXT_PAGE_WAIT)
  end

  def advance_message_state(messages)
    return state['messages_offset'] += Waha::HistoryImportJob::PAGE_SIZE unless messages.empty?

    state['chats_offset'] += 1
    state['messages_offset'] = 0
    state['chat_id'] = nil
  end

  def finish_or_reconcile
    current_pass = state['pass']
    reconciliation_wait = Waha::HistoryImportJob::RECONCILIATION_WAIT
    if current_pass < reconciliation_wait.length
      reset_for_reconciliation
      persist_state.call(context.channel, state)
      schedule(reconciliation_wait.fetch(current_pass))
      return
    end

    state['status'] = 'completed'
    state['finished_at'] = Time.current.to_i
    persist_state.call(context.channel, state)
  end

  def reset_for_reconciliation
    state['pass'] += 1
    state['chats_offset'] = 0
    state['messages_offset'] = 0
    state['chat_id'] = nil
  end

  def import_count(result, key)
    value = result.fetch(key)
    error = Waha::HistoryImportJob::InvalidResponseError
    raise error, 'import_count_invalid' unless value.is_a?(Integer) && value >= 0

    value
  end

  def schedule(wait)
    Waha::HistoryImportJob.set(wait: wait).perform_later(context.inbox_id)
  end
end
