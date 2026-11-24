# O cartão fidelidade e os cupons da conta (#3100): ver o painel é administrador ou `fidelidade_view`; criar e mudar o
# cartão, pausar, ligar de novo e dar ou tirar carimbos à mão é administrador ou `fidelidade_manage` (manage implica
# view, Enterprise::AccountUser). No OSS, permission_granted? é administrator?.
#
# O que é do dia a dia na ficha (ver o cartão da pessoa, dar o prêmio) não passa por aqui: segue quem pode ver e mexer
# no contato (decisão D1 do Rodrigo, 23/11).
class Fidelidade::ProgramaPolicy < ApplicationPolicy
  def view?
    granted?('fidelidade_view')
  end

  def manage?
    granted?('fidelidade_manage')
  end

  private

  def granted?(key)
    account_user&.permission_granted?(key) || false
  end
end
