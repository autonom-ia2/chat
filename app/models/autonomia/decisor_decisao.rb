# Uma resposta do Decisor (#858) sobre UMA mensagem de uma conversa.
#
# A linha é única por (decisor, conversa, mensagem): a segunda regra que pergunta a mesma coisa sobre
# a mesma mensagem reaproveita esta resposta, e o Jev é chamado uma vez só.
#
# `proximo_passo` é o índice da ação em que a automação retoma, quando a resposta chega depois
# (dúvida resolvida pelo Guia ou por uma pessoa). `motivo` guarda só a justificativa curta, nunca a conversa.
class Autonomia::DecisorDecisao < ApplicationRecord
  self.table_name = 'autonomia_decisor_decisoes'

  STATUSES = %w[decidida duvida decidida_pelo_guia esperando_pessoa resolvida vencida sem_cota].freeze
  # Uma dúvida parada mais do que isto não retoma mais a automação: mover card ou mandar mensagem dias
  # depois agiria fora de hora.
  PRAZO_PESSOA = 2.days
  DECIDIDAS = %w[decidida decidida_pelo_guia resolvida].freeze

  belongs_to :decisor, class_name: 'Autonomia::Decisor', inverse_of: :decisoes
  belongs_to :account
  belongs_to :automation_rule, optional: true
  belongs_to :conversation
  belongs_to :message
  belongs_to :resolvida_por, class_name: 'User', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :message_id, uniqueness: { scope: [:decisor_id, :conversation_id] }

  scope :esperando_pessoa, -> { where(status: 'esperando_pessoa') }

  def decidida?
    DECIDIDAS.include?(status)
  end

  def vencida_por_prazo?
    status == 'esperando_pessoa' && created_at < PRAZO_PESSOA.ago
  end
end
