# Marcar pela agenda no painel (#1265). A mesma régua do link por cliente (`Crm::BookingInvitePolicy#create?`): quem
# pode atender pelo agendamento (`HostEligibility`: administrador, agente sem função ou função com `crm_view` ou
# `crm_admin`). Configurar páginas (`agendamento_manage`) não é preciso para marcar a reunião de um cliente. O
# controller confere ainda que a pessoa pode editar o card (`CardPolicy#update?`) ou ver o contato, como o
# "Agendar reunião" pelo Google/Microsoft (`MeetingsController#create`).
class Crm::BookingPageMeetingPolicy < ApplicationPolicy
  def index?
    member?
  end

  def slots?
    member?
  end

  def create?
    member?
  end

  private

  def member?
    Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
  end
end
