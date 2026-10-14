# Multifunil 5/11 (#1145): uma decisão da IA sobre o assunto da conversa, uma por mensagem recebida.
#
# pending: reservada, a IA ainda está pensando. superseded: uma mensagem mais nova decidiu no lugar desta.
# action: o que a decisão pede — none (nada), rename (dar nome ao assunto atual), focus (voltar a outro assunto
# aberto), create (assunto novo no funil). state: o que aconteceu — applied (feito, modo Automática), suggested
# (esperando uma pessoa, modo Sugerir), expired (sugestão vencida por outra), kept (nada a mudar), doubt (a IA não teve
# certeza: nada muda), no_content, no_quota, failed.
class Crm::SubjectDecision < ApplicationRecord
  self.table_name = 'crm_subject_decisions'

  ACTIONS = %w[none rename focus create].freeze
  STATES = %w[pending applied suggested expired accepted dismissed kept superseded doubt no_content no_quota failed].freeze
  MAX_TITLE = 80

  belongs_to :account
  belongs_to :conversation
  belongs_to :message, optional: true
  belongs_to :card, class_name: 'Crm::Card', optional: true
  belongs_to :pipeline, class_name: 'Crm::Pipeline', optional: true

  validates :action, inclusion: { in: ACTIONS }
  validates :state, inclusion: { in: STATES }
  validates :mode, presence: true
  validates :title, length: { maximum: MAX_TITLE }

  scope :suggested, -> { where(state: 'suggested') }
end
