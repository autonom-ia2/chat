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

    # CRM › Números por papel (#1897, F3 do #1871): a visão "Só eu" e o fim da visão da equipe para o agente comum.
    def self.numeros_lentes_enabled?(account)
      account.present? && account.feature_enabled?('crm_numeros_lentes')
    end

    # Metas do mês por pessoa (#1991, F4 do #1871): a gaveta "Metas do mês" e a meta no topo de "Só eu".
    def self.metas_enabled?(account)
      account.present? && account.feature_enabled?('crm_metas')
    end

    # A visão "Equipe" nova (#1992, F5 do #1871) só existe junto da "Só eu": as duas flags.
    def self.numeros_equipe_enabled?(account)
      numeros_lentes_enabled?(account) && account.feature_enabled?('crm_numeros_equipe')
    end

    # Números › "De onde vieram os clientes" (#2001, F6): abre pela visão "Equipe" nova, então depende dela.
    def self.numeros_origens_enabled?(account)
      numeros_equipe_enabled?(account) && account.feature_enabled?('crm_numeros_origens')
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
