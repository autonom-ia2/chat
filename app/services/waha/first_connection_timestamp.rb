class Waha::FirstConnectionTimestamp
  class Error < StandardError; end

  HISTORY_MARKER = 'waha_history_import'.freeze
  WORKING_AT_KEY = 'working_at_ms'.freeze
  CUTOFF_VERSION_KEY = 'cutoff_version'.freeze
  CUTOFF_VERSION = 2
  MAX_TIMESTAMP_MS = 9_000_000_000_000_000
  MARKER_STATUSES = %w[waiting_connection running completed failed].freeze

  def initialize(inbox:, user:, session:, working_at_ms:)
    @inbox = inbox
    @user = user
    @session = session
    @working_at_ms = working_at_ms
  end

  def perform
    validate_request!

    @inbox.channel.with_lock do
      attributes = @inbox.channel.additional_attributes.to_h.deep_stringify_keys
      return :ignored unless waha_channel?(attributes)
      return :ignored unless history_marker_present?(attributes)

      validate_channel_identity!(attributes)
      marker = attributes.fetch(HISTORY_MARKER)
      return already_recorded!(marker) if marker.key?(WORKING_AT_KEY)

      validate_marker!(marker)

      marker[WORKING_AT_KEY] = @working_at_ms
      marker[CUTOFF_VERSION_KEY] = CUTOFF_VERSION
      attributes[HISTORY_MARKER] = marker
      @inbox.channel.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
      @inbox.channel.reload
      :recorded
    end
  end

  private

  def validate_request!
    raise Error, 'history_connection_invalid' unless @inbox && @user.is_a?(User)
    raise Error, 'history_connection_invalid' unless @session.is_a?(String) && @session.present?
    raise Error, 'history_connection_invalid' unless valid_timestamp_type?
  end

  def valid_timestamp_type?
    @working_at_ms.is_a?(Integer) && @working_at_ms.positive? && @working_at_ms <= MAX_TIMESTAMP_MS
  end

  def waha_channel?(attributes)
    @inbox.channel.is_a?(Channel::Api) && attributes['provider'] == 'waha'
  end

  def history_marker_present?(attributes)
    attributes[HISTORY_MARKER].is_a?(Hash)
  end

  def validate_channel_identity!(attributes)
    owner_id = attributes['account_token_owner_user_id']
    valid_owner = owner_id.is_a?(Integer) && owner_id == @user.id
    valid_session = attributes['session'] == @session
    raise Error, 'history_connection_invalid' unless valid_owner && valid_session
  end

  def validate_marker!(marker)
    raise Error, 'history_connection_invalid' unless marker['status'] == 'waiting_connection'

    started_at = marker['started_at']
    raise Error, 'history_connection_invalid' unless started_at.is_a?(Integer) && started_at.positive?

    now_ms = (Time.current.to_f * 1000).floor
    started_at_ms = started_at * 1000
    valid_range = @working_at_ms.between?(started_at_ms, now_ms)
    raise Error, 'history_connection_invalid' unless valid_range
  end

  def already_recorded!(marker)
    raise Error, 'history_connection_invalid' unless valid_recorded_marker?(marker)

    :already_recorded
  end

  def valid_recorded_marker?(marker)
    return false unless marker[CUTOFF_VERSION_KEY] == CUTOFF_VERSION
    return false unless MARKER_STATUSES.include?(marker['status'])

    timestamp = marker[WORKING_AT_KEY]
    started_at = marker['started_at']
    return false unless valid_timestamp?(timestamp)
    return false unless valid_started_at?(started_at)

    timestamp.between?(started_at * 1000, (Time.current.to_f * 1000).floor)
  end

  def valid_timestamp?(timestamp)
    timestamp.is_a?(Integer) && timestamp.positive? && timestamp <= MAX_TIMESTAMP_MS
  end

  def valid_started_at?(started_at)
    started_at.is_a?(Integer) && started_at.positive?
  end
end
