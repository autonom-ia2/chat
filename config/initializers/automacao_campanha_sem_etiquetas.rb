# frozen_string_literal: true

# Lote 5 da Automação livre (#2681): a campanha disparada pela automação deixa de fora quem tem uma etiqueta excluída
# (Autonomia::Automacao::CampanhaSemEtiquetas). Fica por cima do overlay do EE e da jornada de campanhas, e só age
# quando o `audience` traz `ExcludeLabel`.
Rails.application.config.to_prepare do
  mod = Autonomia::Automacao::CampanhaSemEtiquetas
  Whatsapp::OneoffCampaignService.prepend(mod) unless mod >= Whatsapp::OneoffCampaignService
end
