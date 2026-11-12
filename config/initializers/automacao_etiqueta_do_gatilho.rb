# frozen_string_literal: true

# G10 da Automação livre (#2499): renomear a etiqueta da conta leva o nome novo ao gatilho de etiqueta; apagar desliga a
# automação ligada que dependia dela (Autonomia::Automacao::EtiquetaDoGatilho). Roda depois do serviço da plataforma.
Rails.application.config.to_prepare do
  mod = Autonomia::Automacao::EtiquetaDoGatilho
  Labels::UpdateService.prepend(mod::AoRenomear) unless Labels::UpdateService.include?(mod::AoRenomear)
  Labels::DestroyService.prepend(mod::AoApagar) unless Labels::DestroyService.include?(mod::AoApagar)
end
