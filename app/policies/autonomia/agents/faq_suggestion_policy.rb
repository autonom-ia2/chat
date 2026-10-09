# Revisão de sugestões de FAQ do agente Autonom.ia (#284 · 2b): listar, aprovar e ignorar mudam o que o
# agente responde, então todas as ações exigem autonomia_manage.
class Autonomia::Agents::FaqSuggestionPolicy < ApplicationPolicy
  def index?
    permission_granted?('autonomia_manage')
  end

  def approve?
    permission_granted?('autonomia_manage')
  end

  def ignore?
    permission_granted?('autonomia_manage')
  end

  private

  def permission_granted?(key)
    account_user&.permission_granted?(key) || false
  end
end
