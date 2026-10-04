# Um registro que uma tarefa longa do Guia vai mudar (#936). Só a referência
# (`record_type` é o recurso da leitura, `record_id` o id que ela devolveu): o
# dado em si é lido de novo na hora do lote, com a permissão do dono.
#
# A lista é congelada quando a tarefa é planejada e não muda mais. Item `feito`
# nunca repete: o lote só pega os `pendente`.
class Autonomia::Guide::TarefaItem < ApplicationRecord
  self.table_name = 'autonomia_guide_task_items'

  PENDENTE = 'pendente'.freeze
  FEITO = 'feito'.freeze
  FALHOU = 'falhou'.freeze
  PULADO = 'pulado'.freeze
  STATUS = [PENDENTE, FEITO, FALHOU, PULADO].freeze
  MAX_ERRO = 255

  belongs_to :tarefa, class_name: 'Autonomia::Guide::Tarefa', foreign_key: :task_id, inverse_of: :itens

  validates :status, inclusion: { in: STATUS }

  scope :pendentes, -> { where(status: PENDENTE).order(:posicao) }

  def concluir!(status, erro = nil)
    update!(status: status, erro: erro.to_s.first(MAX_ERRO).presence)
  end
end
