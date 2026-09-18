# Revisão de sugestões de FAQ do agente Autonom.ia (#284 · 2b): mesma regra da área de agentes (#452) —
# ver exige autonomia_view; aprovar/ignorar muda o que o agente responde, então exige autonomia_manage.
class Autonomia::Agents::FaqSuggestionPolicy < ApplicationPolicy
  def index?
    permission_granted?('autonomia_view')
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
