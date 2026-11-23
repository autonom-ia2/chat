# Base das telas da Fidelidade (#3100): o cartão da conta e os números do painel. Ver pede `fidelidade_view`; o que
# muda o cartão pede `fidelidade_manage` (Fidelidade::ProgramaPolicy).
class Api::V1::Accounts::Fidelidade::BaseController < Api::V1::Accounts::BaseController
  private

  def conferir(permissao)
    authorize(::Fidelidade::Programa, permissao, policy_class: ::Fidelidade::ProgramaPolicy)
  end

  def programa
    @programa ||= ::Fidelidade::Programa.da_conta(Current.account)
  end
end
