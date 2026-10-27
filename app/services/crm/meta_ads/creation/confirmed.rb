# O que a chamada real já confirmou para criar anúncio (#2198, ponto 12 e "Confirmar na chamada real"). A tela só mostra
# o que está aqui, e o servidor recusa o resto. Hoje é o caso mínimo que a documentação da Meta já garante: WhatsApp e
# site, WhatsApp só em Automático ("Só Instagram" e "Só Facebook" com WhatsApp esperam o item 2; Messenger, o item 9;
# Direct do Instagram, o item 1). Cada item que o diagnóstico confirmar entra aqui num PR.
module Crm::MetaAds::Creation::Confirmed
  PLACEMENTS = %w[AUTO INSTAGRAM FACEBOOK].freeze
  PLACEMENTS_BY_DESTINATION = {
    'WHATSAPP' => %w[AUTO],
    'WEBSITE' => PLACEMENTS
  }.freeze
  DESTINATIONS = PLACEMENTS_BY_DESTINATION.keys.freeze

  def self.payload
    { destinations: DESTINATIONS, placements_by_destination: PLACEMENTS_BY_DESTINATION }
  end

  def self.placement?(destination, placement)
    PLACEMENTS_BY_DESTINATION.fetch(destination, []).include?(placement)
  end
end
