# Uma procura lida (#2251): o assunto de uma conversa, cortado quando o assunto muda. Os campos de filtro ficam em
# coluna; `dados` guarda os cortes ({id do corte => faixa}), o resumo e o porquê da venda perdida, textos da leitura
# que só a tela da conta mostra.
class Autonomia::Desempenho::Procura < ApplicationRecord
  self.table_name = 'autonomia_desempenho_procuras'

  include Autonomia::Desempenho::Sujeito

  belongs_to :conversation

  validates :ordem, numericality: { only_integer: true, greater_than: 0 }
  validates :ordem, uniqueness: { scope: %i[account_id sujeito_type sujeito_id conversation_id] }
  validates :inicio_em, :fim_em, presence: true
  validates :versao_ficha, numericality: { only_integer: true, greater_than: 0 }
  validate :fim_depois_do_inicio
  validate :dados_e_objeto
  validate :conversa_da_mesma_conta

  private

  def fim_depois_do_inicio
    errors.add(:fim_em, :invalid) if inicio_em && fim_em && fim_em < inicio_em
  end

  def dados_e_objeto
    errors.add(:dados, :invalid) unless dados.is_a?(Hash)
  end

  def conversa_da_mesma_conta
    errors.add(:conversation, :invalid) if conversation.present? && conversation.account_id != account_id
  end
end
