# Conversa aberta na campanha do WhatsApp oficial (#1335, épico #1320): quem falou com a caixa nas últimas 24 horas recebe
# a mensagem escrita da campanha (sem modelo); os outros, o modelo. Atrás da flag `campaign_open_window_text`.
module CampaignJourney::ConversaAberta
  FLAG = 'campaign_open_window_text'.freeze

  # O envio do texto vive no caminho Enterprise (CampaignRecipient): sem ele, nada é oferecido nem gravado.
  def self.enabled?(account)
    ChatwootApp.enterprise? && account.feature_enabled?(FLAG)
  end

  # #1456 (decisão do Rodrigo): cupom (botão COPY_CODE), oferta com prazo (LIMITED_TIME_OFFER) ou carrossel só chegam
  # no modelo completo. Com eles não há mensagem escrita: todos recebem o modelo. Lido da estrutura do modelo da Meta
  # (Whatsapp::Templates::SendableFormat), nunca do texto. Mesma regra na tela: `soModeloCompleto` (formatoNaCampanha.js).
  RICH_COMPONENTS = %w[LIMITED_TIME_OFFER CAROUSEL].freeze
  RICH_BUTTON = 'COPY_CODE'.freeze

  def self.so_modelo_completo?(template)
    components = Whatsapp::Templates::SendableFormat.hashes(template.is_a?(Hash) ? template['components'] : nil)
    components.any? { |component| RICH_COMPONENTS.include?(component['type'].to_s.upcase) } ||
      Whatsapp::Templates::SendableFormat.button_types(components).include?(RICH_BUTTON)
  end
end
