# frozen_string_literal: true

# Horário único da caixa (#1619): fuso da conta na caixa e SLA sem o calendário de caixa do CRM, atrás da flag de
# conta `horario_unico_caixa`. Ver app/models/autonomia/horario_unico_caixa.rb.
Rails.application.config.to_prepare do
  Inbox.prepend(Autonomia::HorarioUnicoCaixa::FusoDaConta) unless Inbox <= Autonomia::HorarioUnicoCaixa::FusoDaConta

  if ChatwootApp.enterprise?
    resolver = Sla::ScheduleResolver.singleton_class
    resolver.prepend(Autonomia::HorarioUnicoCaixa::ScheduleResolver) unless resolver <= Autonomia::HorarioUnicoCaixa::ScheduleResolver
  end
end
