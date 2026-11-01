# Uma linha por passo de uma execução, para o histórico (#2414, F2 #2452). `motivo` é a chave i18n do porquê
# (pulado ou falhou); `dados` guarda ids e o custo de IA (D8), nunca o texto da conversa. Sai depois de RETENCAO
# (Autonomia::Automacao::LimparRegistrosJob).
class Autonomia::Automacao::Registro < ApplicationRecord
  self.table_name = 'autonomia_automacao_registros'

  RESULTADOS = %w[ok pulado falhou].freeze
  RETENCAO = 30.days

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'
  belongs_to :execucao, class_name: 'Autonomia::Automacao::Execucao', inverse_of: :registros

  validates :passo, presence: true
  validates :resultado, inclusion: { in: RESULTADOS }
  validate :da_mesma_execucao

  private

  # Execução de outra conta prenderia a exclusão daquela conta nesta chave estrangeira.
  def da_mesma_execucao
    errors.add(:execucao, :invalid) if execucao && (execucao.account_id != account_id || execucao.automacao_id != automacao_id)
  end
end
