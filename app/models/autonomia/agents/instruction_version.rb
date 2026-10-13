# == Schema Information
#
# Table name: autonomia_agent_instruction_versions
#
#  id                 :bigint           not null, primary key
#  instruction        :text             not null
#  instruction_hash   :string           not null
#  metadata           :jsonb            not null
#  reason             :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#  created_by_id      :bigint
#
# Indexes
#
#  idx_autonomia_instruction_versions_agent_created  (autonomia_agent_id,created_at)
#  idx_autonomia_instruction_versions_on_account_id  (account_id)
#  idx_autonomia_instruction_versions_on_agent_id    (autonomia_agent_id)
#  idx_autonomia_instruction_versions_on_created_by  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class Autonomia::Agents::InstructionVersion < ApplicationRecord
  self.table_name = 'autonomia_agent_instruction_versions'

  belongs_to :agent, class_name: 'Autonomia::Agents::Agent',
                     foreign_key: :autonomia_agent_id, inverse_of: :instruction_versions
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  # O HISTÓRICO GUARDA TUDO O QUE O AGENTE ACEITA. Sem limite declarado, esta coluna herdava o teto
  # genérico de texto do `ApplicationRecord` (20.000), menor que o do agente: instrução entre os dois era
  # salva no agente e perdida no histórico, com um erro só no log.
  validates :instruction, presence: true, length: { maximum: Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH }
  validates :instruction_hash, presence: true
  validates :reason, presence: true

  # #1428 — a aplicação do Construtor que não mudou nada fica no banco (rastro), mas não vira linha na lista.
  scope :na_lista, -> { where.not('metadata @> ?', { sem_mudanca: true }.to_json) }

  # #1484 — o texto só sai de versão gravada em modo MANUAL (texto do próprio dono). Quem decide é o modo da
  # VERSÃO, nunca o modo atual do agente: a instrução gerada pelo Construtor não aparece nem depois que o
  # agente passa a manual. Versão antiga, sem retrato: só a edição manual (gravada sempre em modo manual).
  def instrucao_visivel?
    agente = metadata.to_h['agente']
    return agente['mode'] == 'manual' if agente.is_a?(Hash)

    reason == 'manual_edit'
  end
end
