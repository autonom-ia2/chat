module Campaigns
  # Parses a user-supplied `scheduled_at` into an absolute instant WITHOUT the
  # silent-UTC footgun.
  #
  # Root cause it fixes: campaign scheduling accepted a naive datetime string
  # (no offset) and let it collapse to UTC — either via AR type-cast on a
  # :datetime column or via `Time.zone.parse` while `Time.zone` is UTC. For a
  # BR (UTC-3) account, "2026-07-10 09:00" then persisted as 09:00 UTC and the
  # campaign fired 3h early (06:00 local).
  #
  # Two legitimate inputs, per the timezone plan (no silent UTC):
  #   1. A string that ALREADY carries an offset/zone (ISO8601 with `Z` or
  #      `±HH:MM`) — the absolute instant is unambiguous; honor it as-is.
  #   2. A NAIVE wall-clock string — interpret it in the account/inbox
  #      operational zone resolved by TimeZoneResolver. If that resolver cannot
  #      find a genuine zone (source :none), we FAIL-CLOSED and raise
  #      NaiveWithoutZoneError so the caller returns 422 instead of scheduling
  #      in UTC at the wrong local time.
  #
  # A Time/DateTime that already encodes a zone (e.g. `2.days.from_now`) is
  # returned as-is.
  class ScheduledAtParser
    # Raised when a naive datetime is supplied but no operational timezone can
    # be resolved to interpret it. Callers should surface this as a 422.
    class NaiveWithoutZoneError < StandardError; end

    # Raised when the value is present but not a parseable datetime at all.
    class InvalidError < StandardError; end

    # Trailing UTC offset: `Z`, `+00:00`, `-0300`, `+03` at end of string.
    OFFSET_SUFFIX = /(?:Z|[+-]\d{2}(?::?\d{2})?)\z/i

    def self.call(value:, account: nil, inbox: nil, contact: nil)
      new(value: value, account: account, inbox: inbox, contact: contact).call
    end

    def initialize(value:, account: nil, inbox: nil, contact: nil)
      @value = value
      @account = account
      @inbox = inbox
      @contact = contact
    end

    def call
      return @value if already_zoned_object?
      raise InvalidError, 'scheduled_at is blank' if @value.blank?

      str = @value.to_s.strip
      return parse_with_offset(str) if offset?(str)

      parse_naive_in_operational_zone(str)
    end

    private

    # Time/DateTime objects already carry a UTC offset, so the absolute instant
    # is unambiguous — never reinterpret them.
    def already_zoned_object?
      @value.is_a?(Time) || @value.is_a?(DateTime) || @value.is_a?(ActiveSupport::TimeWithZone)
    end

    def offset?(str)
      OFFSET_SUFFIX.match?(str)
    end

    def parse_with_offset(str)
      Time.zone.parse(str) || raise(InvalidError, "unparseable scheduled_at: #{str}")
    end

    def parse_naive_in_operational_zone(str)
      resolution = TimeZoneResolver.for(contact: @contact, account: @account, inbox: @inbox)
      unless resolution.resolved?
        raise NaiveWithoutZoneError,
              'scheduled_at has no timezone and no operational timezone is configured'
      end

      instant = resolution.zone.parse(str)
      raise InvalidError, "unparseable scheduled_at: #{str}" if instant.nil?

      instant
    end
  end
end
