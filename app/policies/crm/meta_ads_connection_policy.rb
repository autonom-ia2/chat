# Anúncios da Meta (#1034). Ver o painel, a conexão e a IA do painel: administrador ou função com `meta_ads_view`
# (funções personalizadas, lote 2, #1794). Conectar, configurar, desconectar e os gestos do consultor: administrador
# ou `meta_ads_manage` (lote 12, #2070), que também vê (manage implica view, Enterprise::AccountUser).
#
# `meta_ads_manage` é chave protegida (regra das duas listas, #1782; decisão D7 do lote 11): só o administrador a
# entrega, ou quem tem o ajuste 'Pode entregar acima do próprio' (grant_above_own), que só o administrador liga
# (CustomRole::DELEGATION_KEYS, CustomRoles::GrantGuard). Ela dá acesso de usuário do sistema da plataforma à conta de anúncios do
# cliente (selection), grava o token, liga o aviso de vendas no funil (meta_sync) e o resumo no WhatsApp do dono.
class Crm::MetaAdsConnectionPolicy < ApplicationPolicy
  def show?
    granted?('meta_ads_view')
  end

  def update?
    granted?('meta_ads_manage')
  end

  def destroy?
    granted?('meta_ads_manage')
  end

  private

  # No OSS, permission_granted? é administrator?; o EE soma as chaves da função personalizada.
  def granted?(key)
    account_user&.permission_granted?(key) || false
  end
end
