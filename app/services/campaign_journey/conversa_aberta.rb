# Conversa aberta na campanha do WhatsApp oficial (#1335, épico #1320): quem falou com a caixa nas últimas 24 horas recebe
# a mensagem escrita da campanha (sem modelo); os outros, o modelo. Atrás da flag `campaign_open_window_text`.
module CampaignJourney::ConversaAberta
  FLAG = 'campaign_open_window_text'.freeze

  def self.enabled?(account)
    account.feature_enabled?(FLAG)
  end
end
