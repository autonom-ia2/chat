# As sugestões de "Do sinal à ação" de um período do painel de desempenho (#2251), em cache. Nesta fase vêm geradas
# fora, junto da carga; o painel só as mostra quando o período guardado é o mesmo que ele calculou (senão os números
# citados seriam de outras datas).
class Autonomia::Desempenho::Recomendacao < ApplicationRecord
  self.table_name = 'autonomia_desempenho_recomendacoes'

  include Autonomia::Desempenho::Sujeito

  PERIODOS = %w[7 30 90 tudo].freeze

  validates :periodo, inclusion: { in: PERIODOS }
  validates :periodo, uniqueness: { scope: %i[account_id sujeito_type sujeito_id] }
  validates :inicio, :fim, :gerada_em, presence: true
  validates :versao_ficha, numericality: { only_integer: true, greater_than: 0 }
  validate :cartoes_sao_lista

  private

  def cartoes_sao_lista
    errors.add(:cartoes, :invalid) unless cartoes.is_a?(Array)
  end
end
