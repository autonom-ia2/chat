# CRM › Números por papel (#1897, F3 do #1871), no molde do Crm::BookingStatsPolicy:
#   - "Só eu": quem trabalha no CRM (administrador e agente; com função, `crm_view`, no EE);
#   - "Equipe": a mesma régua dos números da equipe (Crm::ReportPolicy: administrador e `crm_view_reports`).
# Quem não tem nenhuma das duas: nada (401).
class Crm::NumerosPolicy < ApplicationPolicy
  def show?
    eu? || equipe?
  end

  def eu?
    account_user.present?
  end

  def equipe?
    Crm::ReportPolicy.new(user_context, record).view?
  end
end

Crm::NumerosPolicy.prepend_mod_with('Crm::NumerosPolicy')
