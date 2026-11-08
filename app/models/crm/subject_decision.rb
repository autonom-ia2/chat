# Multifunil 5/11 (#1145): uma decisão da IA sobre o assunto da conversa, uma por mensagem recebida.
#
# pending: reservada, a IA ainda está pensando. superseded: uma mensagem mais nova decidiu no lugar desta.
# action: o que a decisão pede — none (nada), rename (dar nome ao assunto atual), focus (voltar a outro assunto
# aberto), create (assunto novo no funil). state: o que aconteceu — applied (feito, modo Automática), suggested
# (esperando uma pessoa, modo Sugerir), expired (sugestão vencida por outra), kept (nada a mudar), doubt (a IA não teve
# certeza: nada muda), no_content, no_quota, failed.
# touched_card_ids (#1693): os cards que a mensagem tocou, o principal primeiro, para a IA do CRM avaliar numa chamada
# só. Nulo: não calculado (sem a flag `crm_avaliar_toda_mensagem`, dúvida, falha); vazio: nenhum assunto ("obrigado!").
# Medição (#2018), só registro: jev_answer é o tipo da opção que o Jev escolheu (sem_assunto, mesmo, card, novo, varios),
# nulo quando ele não respondeu. review_reason é por que o modelo maior foi chamado (certeza_baixa, pedido_novo, varios,
# nome_do_atual, nome_provisorio; o primeiro que vale, nessa ordem), nulo quando o Jev decidiu sozinho. Com o modelo
# maior, a decisão final pode diferir do jev_answer.
# Nome genérico (#2163, flag `crm_ia_nome_provisorio`): reason `mesmo_assunto` na decisão "o mesmo assunto" (o card
# carrega um pedido), `nome_refinado` no nome genérico trocado pelo específico, `card_ja_tinha_pedido` no card novo que
# nasceu em vez de renomear o card sem nome que já carregava um pedido.
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
