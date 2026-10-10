module Crm
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    def self.enabled?
      BOOLEAN.cast(ENV.fetch('CRM_KANBAN_ENABLED', false))
    end

    # Meetings are available to EVERY account when the install-level flag is on —
    # each account is a separate client that schedules through its OWN connected
    # Google/Microsoft calendar mailbox (no per-account rollout flag). The `account`
    # arg is kept for call-site stability but no longer gates availability.
    def self.calendar_meetings_enabled?(_account = nil)
      BOOLEAN.cast(ENV.fetch('CRM_CALENDAR_MEETINGS_ENABLED', false))
    end

    # Agendamento WhatsApp-first (#1187): liga por conta (flag `crm_booking_v2`, piloto no Super Admin) e só
    # existe se o calendário de reuniões da instalação estiver ligado.
    def self.booking_v2_enabled?(account)
      return false if account.blank?

      calendar_meetings_enabled? && account.feature_enabled?('crm_booking_v2')
    end

    def self.calendar_ms_simulate?
      return BOOLEAN.cast(ENV['CRM_CALENDAR_MS_SIMULATE']) == true if ENV.key?('CRM_CALENDAR_MS_SIMULATE')

      !Rails.env.production?
    end

    def self.calendar_google_simulate?
      return BOOLEAN.cast(ENV['CRM_CALENDAR_GOOGLE_SIMULATE']) == true if ENV.key?('CRM_CALENDAR_GOOGLE_SIMULATE')

      !Rails.env.production?
    end
  end
end
