# Com a flag `horario_unico_caixa` (#1619), o SLA não lê o calendário de caixa do CRM: fica o calendário de quem é o
# responsável, e sem ele o Sla::DueAtCalculator cai no horário do Chatwoot (Sla::BusinessHoursService). Desligada,
# `super` resolve como sempre (responsável > caixa). Prepend no singleton de Sla::ScheduleResolver.
module Autonomia::HorarioUnicoCaixa::ScheduleResolver
  def for_conversation(conversation)
    return super unless Autonomia::HorarioUnicoCaixa.ligado?(conversation.account)
    return nil if conversation.assignee_id.blank?

    schedule = Crm::ServiceSchedule.find_by(account_id: conversation.account_id, owner_type: 'User', owner_id: conversation.assignee_id)
    schedule&.usable? ? schedule : nil
  end
end
