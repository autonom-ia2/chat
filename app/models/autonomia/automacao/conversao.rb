# A regra antiga que virou automação livre (#2414 F9, #2568; desenho em docs/automacao/F9-conversao-do-antigo.md).
# `estado_antes` é o backup da linha antiga, para a reversão devolvê-la como estava. O índice único
# (account_id, antigo_tipo, antigo_id) é a trava: uma regra antiga tem no máximo uma conversão vigente. A reversão
# apaga a linha.
class Autonomia::Automacao::Conversao < ApplicationRecord
  self.table_name = 'autonomia_automacao_conversoes'

  ANTIGOS = %w[AutomationRule Crm::StageAutomation].freeze

  belongs_to :account
  belongs_to :definicao, class_name: 'Autonomia::Automacao::Definicao'

  validates :antigo_tipo, inclusion: { in: ANTIGOS }
  validates :antigo_id, presence: true, uniqueness: { scope: %i[account_id antigo_tipo] }
  validates :estado_antes, presence: true
end
