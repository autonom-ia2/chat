# Pré-voo (#1624) de UM follow-up: ver Crm::FollowUps::Preflight. Fila `low`: a IA e a Meta demoram e não podem segurar o
# envio dos follow-ups que já venceram.
class Crm::FollowUpPreflightRunJob < ApplicationJob
  queue_as :low

  def perform(follow_up_id)
    follow_up = Crm::FollowUp.find_by(id: follow_up_id)
    return if follow_up.nil?

    Crm::FollowUps::Preflight.new(follow_up: follow_up).call
  end
end
