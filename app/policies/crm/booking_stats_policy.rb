# Painel de resultados do agendamento (#1194, J7-A5, J8-A12), no padrão de funções personalizadas:
#   - "Meus números": quem atende pelo agendamento (`HostEligibility`: administrador, agente sem função ou função
#     com `crm_view`/`crm_admin`) e quem tem `agendamento_view` (ou `_manage`);
#   - números da equipe: administrador ou `agendamento_view` (`_manage` implica `_view`);
#   - "Enviar de novo": quem pode gerar e entregar o link por cliente (`Crm::BookingInvitePolicy#create?`).
# Função sem CRM e sem o módulo: nada (401).
class Crm::BookingStatsPolicy < ApplicationPolicy
  def show?
    member? || team?
  end

  def opened_not_booked?
    show?
  end

  def team?
    account_user&.permission_granted?('agendamento_view') || false
  end

  def resend?
    member?
  end

  private

  def member?
    Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
  end
end
