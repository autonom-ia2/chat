# Anúncios da Meta (#1034). Ver o painel, a conexão e a IA do painel: administrador ou função com `meta_ads_view`
# (funções personalizadas, lote 2, #1794). Conectar, configurar, desconectar e os gestos do consultor seguem só do
# administrador: viram `meta_ads_manage`, chave protegida, no lote das protegidas (#1784, modelo seção 5.6).
class Crm::MetaAdsConnectionPolicy < ApplicationPolicy
  def show?
    account_user&.permission_granted?('meta_ads_view') || false
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
