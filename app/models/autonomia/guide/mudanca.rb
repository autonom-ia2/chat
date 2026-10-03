# == Schema Information
#
# Table name: autonomia_guide_changes
#
#  id           :bigint           not null, primary key
#  antes        :jsonb            not null
#  depois       :jsonb            not null
#  operacao     :string           not null
#  ordem        :integer          not null
#  passo        :integer          not null
#  record_type  :string           not null
#  tabela       :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  execution_id :bigint           not null
#  record_id    :bigint           not null
#
# Indexes
#
#  index_autonomia_guide_changes_on_execution_id            (execution_id)
#  index_autonomia_guide_changes_on_execution_id_and_ordem  (execution_id,ordem)
#
# Foreign Keys
#
#  fk_rails_...  (execution_id => autonomia_guide_executions.id) ON DELETE => cascade
#

# Uma linha do banco que o Guia criou, alterou ou apagou (#855).
#
# `antes` e `depois` guardam só as colunas que importam para voltar, no formato
# do próprio Postgres (row_to_json). Criar guarda o `depois` (para saber se
# alguém mexeu desde então); alterar guarda as colunas mudadas nos dois lados;
# apagar guarda a linha inteira no `antes`, para pôr de volta igual.
class Autonomia::Guide::Mudanca < ApplicationRecord
  self.table_name = 'autonomia_guide_changes'

  OPERACOES = %w[create update destroy].freeze

  belongs_to :execucao, class_name: 'Autonomia::Guide::Execucao', foreign_key: :execution_id,
                        inverse_of: :mudancas

  validates :operacao, inclusion: { in: OPERACOES }
end
