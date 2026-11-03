# As automações da Automação livre (#2414 F5, D2/D4): ver pede `automation_view`; montar, salvar, ligar e desligar pedem
# `automation_manage`. Sem função personalizada, só o administrador passa (AccountUser#permission_granted?).
class Autonomia::Automacao::DefinicaoPolicy < ApplicationPolicy
  def passos? = ver?
  def index? = ver?
  def show? = ver?
  def create? = gerenciar?
  def update? = gerenciar?
  def ligar? = gerenciar?
  def desligar? = gerenciar?

  private

  def ver?
    account_user&.permission_granted?('automation_view') == true
  end

  def gerenciar?
    account_user&.permission_granted?('automation_manage') == true
  end
end
