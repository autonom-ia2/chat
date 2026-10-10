# Link por cliente (#1190, J8-A3/A7). Quem gera o link precisa ver o cliente: isso o controller confere com as
# policies do sistema (card, conversa ou contato). Aqui fica o que é do convite:
#   - usar convites: membro da conta sem função (agente ou administrador) ou função com alguma chave de CRM ou de
#     agendamento (a mesma régua de quem pode atender, `HostEligibility`). Função sem CRM não usa.
#   - ver e entregar: o administrador e `agendamento_view` (ou `_manage`) veem todos; os demais, só os próprios.
#   - cancelar: o administrador e `agendamento_manage` cancelam qualquer um; os demais, só os próprios.
class Crm::BookingInvitePolicy < ApplicationPolicy
  def index?
    member?
  end

  def create?
    member?
  end

  def show?
    member? && same_account? && (granted?('agendamento_view') || own?)
  end

  def deliver?
    show?
  end

  def destroy?
    member? && same_account? && (granted?('agendamento_manage') || own?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(account_id: account.id)
      return base if account_user&.permission_granted?('agendamento_view')

      base.where(created_by_id: user.id)
    end
  end

  private

  def member?
    Crm::BookingV2::HostEligibility.eligible?(account: account, user: user)
  end

  def own?
    record.created_by_id.present? && record.created_by_id == user&.id
  end

  def granted?(key)
    account_user&.permission_granted?(key) || false
  end

  def same_account?
    account.present? && record.account_id == account.id
  end
end
