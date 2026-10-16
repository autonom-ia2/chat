# Horário único da caixa (#1619, flag de conta `horario_unico_caixa`, #1649).
# Ligada, a caixa tem um horário só: o do Chatwoot (`working_hours` + `working_hours_enabled`), lido no fuso da conta.
# - `FusoDaConta` (prepend em Inbox): `inbox.timezone` devolve o fuso da conta (`reporting_timezone`). A coluna fica
#   como está, então desligar a flag volta ao fuso gravado em cada caixa.
# - `ScheduleResolver` (prepend em Sla::ScheduleResolver) e `EngagementGate#service_schedule`: o calendário de caixa
#   do CRM (`Crm::ServiceSchedule` com dono Inbox) deixa de ser lido; o da pessoa continua no SLA.
# Desligada (padrão): tudo como antes. Os prepends ficam em config/initializers/autonomia_horario_unico_caixa.rb.
module Autonomia::HorarioUnicoCaixa
  FEATURE = 'horario_unico_caixa'.freeze

  def self.ligado?(account)
    account.present? && account.feature_enabled?(FEATURE)
  end
end
