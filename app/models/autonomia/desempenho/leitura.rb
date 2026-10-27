# Até onde uma conversa foi lida para o painel de desempenho (#2251), uma linha por conversa e sujeito. É a fila da
# atualização automática (Issue própria): conversa com mensagem depois de `lida_ate_em` volta a ser lida, e
# `versao_ficha` diz com que ficha a leitura foi feita.
class Autonomia::Desempenho::Leitura < ApplicationRecord
  self.table_name = 'autonomia_desempenho_leituras'

  include Autonomia::Desempenho::Sujeito

  STATUS = %w[lida lida_em_parte minima nao_lida].freeze

  belongs_to :conversation

  validates :status, inclusion: { in: STATUS }
  validates :lida_ate_em, presence: true
  validates :versao_ficha, numericality: { only_integer: true, greater_than: 0 }
  validates :conversation_id, uniqueness: { scope: %i[account_id sujeito_type sujeito_id] }
  validate :conversa_da_mesma_conta

  private

  def conversa_da_mesma_conta
    errors.add(:conversation, :invalid) if conversation.present? && conversation.account_id != account_id
  end
end
