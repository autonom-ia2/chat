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

  # #1428 — a aplicação do Construtor que não mudou nada fica no banco (rastro), mas não vira linha na lista. Nem a
  # primeira escrita de um turno com correção (`fora_da_lista`): uma aplicação, uma linha.
  scope :na_lista, lambda {
    where.not('metadata @> ?', { sem_mudanca: true }.to_json).where.not('metadata @> ?', { fora_da_lista: true }.to_json)
  }

  # Versões que o Construtor grava: a instrução é dele, seja qual for o modo gravado.
  DO_CONSTRUTOR = %w[builder_create builder_adjust].freeze

  # #1484 — o texto só sai quando foi ESCRITO PELO DONO. A edição à mão (`manual_edit`) é a prova: é a única
  # gravação que nasce do texto que a pessoa digitou. As outras versões de um agente manual (`base`,
  # `antes_de_voltar`, `rollback`, e as antigas sem retrato) só mostram o texto se ele é um que o dono escreveu
  # (o mesmo hash de uma `manual_edit` deste agente) — um agente manual que recebeu o Construtor antes da recusa
  # do #1514 não expõe a instrução gerada por nenhum caminho. Versão do Construtor e versão com retrato guiado,
  # nunca. Na dúvida, oculta.
  # `escritos_pelo_dono`: os hashes das `manual_edit` do agente (o controller passa uma vez para a lista toda).
  def instrucao_visivel?(escritos_pelo_dono = agent.hashes_escritos_pelo_dono)
    return false if DO_CONSTRUTOR.include?(reason)
    return true if reason == 'manual_edit'

    agente = metadata.to_h['agente']
    # Retrato de um agente guiado: a instrução é do Construtor, mesmo que o texto coincida.
    return false if agente.is_a?(Hash) && agente['mode'] != 'manual'

    escritos_pelo_dono.include?(instruction_hash)
  end
end
