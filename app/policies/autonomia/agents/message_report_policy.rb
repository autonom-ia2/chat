# Feedback do atendente numa resposta do agente Autonom.ia (#284): QUALQUER membro da conta
# (agente ou administrador) pode marcar "resposta errada". A área administrativa dos agentes
# continua fechada (Autonomia::BaseController); este é o único endpoint aberto ao atendente.
class Autonomia::Agents::MessageReportPolicy < ApplicationPolicy
  def create?
    account_user.present?
  end
end
