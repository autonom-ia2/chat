# Conversa aberta na campanha do WhatsApp oficial (#1335, épico #1320): quem falou com a caixa nas últimas 24 horas recebe
# a mensagem escrita da campanha (sem modelo); os outros, o modelo. Atrás da flag `campaign_open_window_text`.
module CampaignJourney::ConversaAberta
  FLAG = 'campaign_open_window_text'.freeze

  # O envio do texto vive no caminho Enterprise (CampaignRecipient): sem ele, nada é oferecido nem gravado.
  def self.enabled?(account)
    ChatwootApp.enterprise? && account.feature_enabled?(FLAG)
  end
end
