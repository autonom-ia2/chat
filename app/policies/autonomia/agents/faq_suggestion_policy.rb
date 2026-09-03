# Revisão de sugestões de FAQ do agente Autonom.ia (#284 · 2b): só administradores da conta (mesma
# regra da área de agentes — o conhecimento aprovado muda o que o agente responde).
class Autonomia::Agents::FaqSuggestionPolicy < ApplicationPolicy
  def index?
    administrator?
  end

  def approve?
    administrator?
  end

  def ignore?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator? || false
  end
end
