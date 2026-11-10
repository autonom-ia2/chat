# frozen_string_literal: true

# Lote 5 da Automação livre (#2681): a campanha disparada pela automação deixa de fora quem tem uma etiqueta excluída
# (Autonomia::Automacao::CampanhaSemEtiquetas). Só age quando o `audience` traz `ExcludeLabel`.
#
# O nome do arquivo faz ele carregar DEPOIS do config/initializers/campaign_journey.rb (os initializers carregam em
# ordem alfabética, e os to_prepare rodam na ordem em que foram registrados). Assim o módulo fica por cima da jornada
# de campanhas e do overlay do EE, e alcança também a campanha ligada a um público importado (audience link), cujo
# público sai do CampaignJourney::AudienceContacts#audience_contacts sem passar pelas etiquetas. O spec do módulo
# confere essa ordem.
Rails.application.config.to_prepare do
  mod = Autonomia::Automacao::CampanhaSemEtiquetas
  Whatsapp::OneoffCampaignService.prepend(mod) unless mod >= Whatsapp::OneoffCampaignService
end
