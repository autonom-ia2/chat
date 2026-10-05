# Credencial de leitura de anúncios da Meta (#1034): só administrador da conta vê e edita. Não
# delega por função personalizada (tokens de integração ficam fora das funções, ver CLAUDE.md).
class Crm::MetaAdsConnectionPolicy < ApplicationPolicy
  def show?
    administrator?
  end

  def update?
    administrator?
  end

  def destroy?
    administrator?
  end

  private

  def administrator?
    account_user&.administrator? || false
  end
end
