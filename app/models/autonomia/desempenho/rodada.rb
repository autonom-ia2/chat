# Uma rodada da leitura automática diária do painel de desempenho (#2301): até onde leu (`corte_em`), como terminou
# e quanto gastou. O painel lê daqui o "Lido até" (corte da última rodada `ok` ou `teto`) e a situação da leitura
# (`sem_ia` ou `teto` quando a última rodada parou por isso).
class Autonomia::Desempenho::Rodada < ApplicationRecord
  self.table_name = 'autonomia_desempenho_rodadas'

  include Autonomia::Desempenho::Sujeito

  STATUS = %w[rodando ok teto sem_ia erro].freeze
  # As que leram de verdade: o "Lido até" sai delas.
  LIDAS = %w[ok teto].freeze

  validates :status, inclusion: { in: STATUS }
  validates :corte_em, :piso_em, :iniciada_em, presence: true
  validates :conversas_lidas, :conversas_pendentes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recentes, -> { order(iniciada_em: :desc, id: :desc) }
end
