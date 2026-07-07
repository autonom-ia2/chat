# Single, safe source of truth for resolving an operational time zone.
#
# Problem it fixes: across the codebase every subsystem invented its own
# fallback chain that terminated in a silent `'UTC'`. Because Rails' default
# `Time.zone` is UTC, `account.reporting_timezone` is usually nil, and WhatsApp
# contacts never carry `additional_attributes['timezone']`, every time-of-day
# decision quietly collapsed to UTC. In BR (UTC-3) an "08–20" window became
# "05–17" local and follow-ups fired at 05:00.
#
# This resolver walks an EXPLICIT chain and, crucially, reports WHICH source
# won via `#source`. The zone is NEVER nil. When nothing valid resolves, the
# zone is UTC but `source` is `:none` — a signal callers that schedule a
# send/window MUST treat as fail-closed (skip/defer, never fire in UTC).
#
# Chain (first VALID wins):
#   contact.additional_attributes['timezone']
#     -> inbox.timezone (only when NON-UTC — see below)
#       -> account.reporting_timezone
#         -> ENV['DEFAULT_OPERATIONAL_TIMEZONE']
#           -> (none) => zone=UTC, source=:none
#
# "Valid" means `ActiveSupport::TimeZone[value]` is present (accepts both IANA
# identifiers and Rails' friendly names). No Brazil (or any region) is ever
# hardcoded here — the operational default is configuration, per cross-project
# multi-tenant safety rules.
#
# Inbox subtlety (the whole point of the H3 rewire): `inbox.timezone` is a
# NOT-NULL column that DEFAULTS to 'UTC'. That default is indistinguishable
# from an operator who genuinely picked UTC, so treating it as a resolved
# business zone would re-introduce the exact silent-UTC footgun this resolver
# exists to kill. We therefore only honor the inbox zone when it is a valid,
# NON-UTC identifier; a plain-default UTC inbox falls through to account/ENV.
# A genuinely non-UTC inbox (e.g. 'Australia/Sydney') resolves as :inbox and
# behaves exactly as before.
class TimeZoneResolver
  ENV_DEFAULT_KEY = 'DEFAULT_OPERATIONAL_TIMEZONE'.freeze
  CONTACT_ATTR_KEY = 'timezone'.freeze
  UTC_ZONE_NAME = 'UTC'.freeze

  Resolution = Struct.new(:zone, :source, keyword_init: true) do
    # True only when a genuine, configured zone was found. Callers scheduling a
    # send/window should fail-closed (defer + WARN) when this is false.
    def resolved?
      source != :none
    end
  end

  # Convenience: just the zone (never nil). Use `.for` when you also need the
  # source to decide fail-closed behavior.
  def self.zone_for(contact: nil, account: nil, inbox: nil)
    self.for(contact: contact, account: account, inbox: inbox).zone
  end

  def self.for(contact: nil, account: nil, inbox: nil)
    new(contact: contact, account: account, inbox: inbox).resolve
  end

  def initialize(contact: nil, account: nil, inbox: nil)
    @contact = contact
    @account = account
    @inbox = inbox
  end

  def resolve
    zone_from(contact_timezone, :contact) ||
      zone_from(inbox_timezone, :inbox) ||
      zone_from(account_timezone, :account) ||
      zone_from(env_default_timezone, :default) ||
      Resolution.new(zone: ActiveSupport::TimeZone[UTC_ZONE_NAME], source: :none)
  end

  private

  # Returns a Resolution when `value` maps to a real ActiveSupport::TimeZone,
  # otherwise nil so the chain falls through to the next candidate.
  def zone_from(value, source)
    return nil if value.blank?

    zone = ActiveSupport::TimeZone[value]
    return nil if zone.nil?

    Resolution.new(zone: zone, source: source)
  end

  def contact_timezone
    attrs = @contact&.additional_attributes
    return nil unless attrs.is_a?(Hash)

    attrs[CONTACT_ATTR_KEY]
  end

  # A plain-default UTC inbox is treated as "unset" so the chain falls through
  # to account/ENV instead of silently locking business decisions to UTC.
  def inbox_timezone
    tz = @inbox&.timezone
    return nil if tz.blank? || tz == UTC_ZONE_NAME

    tz
  end

  def account_timezone
    @account&.reporting_timezone
  end

  def env_default_timezone
    ENV.fetch(ENV_DEFAULT_KEY, nil)
  end
end
