# O que a chamada real já confirmou para criar anúncio (#2198, ponto 12 e "Confirmar na chamada real"). A tela só mostra
# o que está aqui, e o servidor recusa o resto. WhatsApp e site, como a documentação da Meta garante; WhatsApp só em
# Automático ("Só Instagram" e "Só Facebook" com WhatsApp esperam o item 2). Messenger e Direct do Instagram entram só em
# Automático (#2560, decisão do Rodrigo de 05/11), com os campos da documentação de anúncio de mensagem; a primeira
# chamada real é o anúncio pausado de teste na conta 18. Perfil do Instagram (#2564) entra só em "Só Instagram"
# (decisão do Rodrigo, 06/11): o anúncio leva ao perfil, que só existe no Instagram. Cada item que o diagnóstico confirmar
# entra aqui num PR.
module Crm::MetaAds::Creation::Confirmed
  PLACEMENTS = %w[AUTO INSTAGRAM FACEBOOK].freeze
  PLACEMENTS_BY_DESTINATION = {
    'WHATSAPP' => %w[AUTO],
    'INSTAGRAM_DIRECT' => %w[AUTO],
    'MESSENGER' => %w[AUTO],
    'WEBSITE' => PLACEMENTS,
    'INSTAGRAM_PROFILE' => %w[INSTAGRAM]
  }.freeze
  DESTINATIONS = PLACEMENTS_BY_DESTINATION.keys.freeze
  # Carrossel em anúncio de Messenger, Direct ou perfil não está confirmado na documentação (#2198, item 6): só WhatsApp e site.
  CAROUSEL_DESTINATIONS = %w[WHATSAPP WEBSITE].freeze

  def self.payload
    { destinations: DESTINATIONS, placements_by_destination: PLACEMENTS_BY_DESTINATION }
  end

  def self.placement?(destination, placement)
    PLACEMENTS_BY_DESTINATION.fetch(destination, []).include?(placement)
  end
end
