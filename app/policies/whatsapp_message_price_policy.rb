# Preço por envio do WhatsApp oficial (#1332): quem vê modelos ou campanhas vê quanto cada envio custa.
class WhatsappMessagePricePolicy < ApplicationPolicy
  def index?
    %w[whatsapp_templates_view campaign_view].any? { |key| @account_user&.permission_granted?(key) } || false
  end
end
