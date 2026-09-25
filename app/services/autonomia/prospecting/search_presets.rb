# Jogadas prontas da busca (#677), com os mesmos ids do Orth
# (lib/services/scoring/presets.ts). O catálogo completo, com filtros, nome e
# visual, mora no front (prospecting/utils/searchPresets.js); aqui fica só o id
# e o modo a que cada jogada pertence, para recusar o que o cliente inventar.
module Autonomia::Prospecting::SearchPresets
  MODES_BY_ID = {
    'vender-site' => 'gbp',
    'gestao-reviews' => 'gbp',
    'otimizacao-gbp' => 'gbp',
    'prova-social' => 'general',
    'mercado-maduro' => 'general',
    'presenca-digital' => 'general'
  }.freeze

  def self.valid_for_mode?(preset_id, score_mode)
    MODES_BY_ID[preset_id.to_s] == score_mode.to_s
  end

  # Jogada pronta no modo dela, ou jogada salva da conta (#732) no modo em que foi salva.
  def self.valid_for?(account:, preset_id:, score_mode:)
    return true if valid_for_mode?(preset_id, score_mode)

    saved = Autonomia::Prospecting::SavedPreset.find_by_preset_id(account, preset_id)
    saved.present? && saved.score_mode == score_mode.to_s
  end
end
