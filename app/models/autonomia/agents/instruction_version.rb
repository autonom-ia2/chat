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
end
