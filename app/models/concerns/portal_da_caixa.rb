# Caixa só se liga a portal da própria conta, e nunca ao portal da plataforma: a Central de Ajuda da
# plataforma não chega ao chat do site nem à caixa de resposta (#501).
module PortalDaCaixa
  extend ActiveSupport::Concern

  included do
    validate :portal_permitido, if: :portal_id_changed?
  end

  private

  def portal_permitido
    return if portal_id.blank?

    alvo = Portal.find_by(id: portal_id)
    return if alvo && alvo.account_id == account_id && alvo.slug != Autonomia::CentralDeAjuda::Publicador::SLUG_PORTAL

    errors.add(:portal_id, :invalid)
  end
end
