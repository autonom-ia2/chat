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
#     -> account.reporting_timezone
#       -> ENV['DEFAULT_OPERATIONAL_TIMEZONE']
#         -> (none) => zone=UTC, source=:none
#
# "Valid" means `ActiveSupport::TimeZone[value]` is present (accepts both IANA
# identifiers and Rails' friendly names). No Brazil (or any region) is ever
# hardcoded here — the operational default is configuration, per cross-project
# multi-tenant safety rules.
class TimeZoneResolver
  ENV_DEFAULT_KEY = 'DEFAULT_OPERATIONAL_TIMEZONE'.freeze
  CONTACT_ATTR_KEY = 'timezone'.freeze

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
      zone_from(account_timezone, :account) ||
      zone_from(env_default_timezone, :default) ||
      Resolution.new(zone: ActiveSupport::TimeZone['UTC'], source: :none)
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

  def account_timezone
    @account&.reporting_timezone
  end

  def env_default_timezone
    ENV.fetch(ENV_DEFAULT_KEY, nil)
  end
end
