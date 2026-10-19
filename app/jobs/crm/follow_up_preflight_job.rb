# Pré-voo (#1624): de minuto em minuto, enfileira um job por follow-up automático que vence nos próximos 10 minutos e ainda
# não tem a marca do pré-voo. Só enfileira: a IA e a Meta podem levar ~10 s cada e não travam o varredor. Quem faz o trabalho
# é o Crm::FollowUpPreflightRunJob (Crm::FollowUps::Preflight).
class Crm::FollowUpPreflightJob < ApplicationJob
  queue_as :scheduled_jobs

  SOURCES = [Crm::FollowUps::ServiceReminderScheduler::SOURCE, Crm::FollowUps::CallbackScheduler::SOURCE].freeze

  def perform(now: Time.current)
    return unless Crm::Config.enabled? && Crm::Ai::Config.enabled?

    candidates(now).find_each do |follow_up|
      Crm::FollowUpPreflightRunJob.perform_later(follow_up.id) if Crm::FollowUps::Preflight.pendente?(follow_up)
    end
  end

  private

  def candidates(now)
    Crm::FollowUp.due_within(now, now + Crm::FollowUps::Preflight::ANTECEDENCIA)
                 .auto_send_message.where("metadata ->> 'source' IN (?)", SOURCES)
  end
end
