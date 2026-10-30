# Quem o painel de desempenho mede (#2251): o agente nosso ('agente', Autonomia::Agents::Agent) ou o robô de outro
# sistema ('robo', AgentBot de webhook). As quatro tabelas do painel guardam o par (sujeito_type, sujeito_id) e
# nascem presas à conta.
module Autonomia::Desempenho::Sujeito
  extend ActiveSupport::Concern

  TIPOS = %w[agente robo].freeze

  included do
    belongs_to :account

    validates :sujeito_type, inclusion: { in: TIPOS }
    validates :sujeito_id, presence: true
    validates :lote, presence: true

    scope :do_sujeito, ->(account, tipo, id) { where(account_id: account.id, sujeito_type: tipo, sujeito_id: id) }
  end
end
