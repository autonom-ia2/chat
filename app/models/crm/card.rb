# == Schema Information
#
# Table name: crm_cards
#
#  id                :bigint           not null, primary key
#  closed_at         :datetime
#  currency          :string           default("BRL"), not null
#  description       :text
#  entered_stage_at  :datetime
#  expected_close_at :datetime
#  last_activity_at  :datetime
#  last_message_at   :datetime
#  lost_reason       :text
#  metadata          :jsonb            not null
#  next_follow_up_at :datetime
#  priority          :integer          default("medium"), not null
#  score             :integer          default(0), not null
#  source            :string
#  status            :integer          default("open"), not null
#  title             :string           not null
#  value_cents       :bigint           default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  contact_id        :bigint
#  conversation_id   :bigint
#  external_id       :string
#  inbox_id          :bigint
#  owner_id          :bigint
#  pipeline_id       :bigint           not null
#  stage_id          :bigint           not null
#  team_id           :bigint
#
# Indexes
#
#  idx_crm_cards_account_pipeline_status_closed  (account_id,pipeline_id,status,closed_at)
#  idx_crm_cards_account_updated                 (account_id,updated_at,id)
#  idx_crm_cards_board                           (account_id,pipeline_id,stage_id,status,id)
#  idx_crm_cards_board_follow_up                 (account_id,pipeline_id,stage_id,status,next_follow_up_at,id)
#  idx_crm_cards_board_inbox                     (account_id,pipeline_id,stage_id,status,inbox_id,id)
#  idx_crm_cards_board_owner                     (account_id,pipeline_id,stage_id,status,owner_id,id)
#  idx_crm_cards_board_priority                  (account_id,pipeline_id,stage_id,status,priority,id)
#  idx_crm_cards_board_team                      (account_id,pipeline_id,stage_id,status,team_id,id)
#  idx_crm_cards_calendar                        (account_id,pipeline_id,expected_close_at,id)
#  idx_crm_cards_contact                         (account_id,contact_id)
#  idx_crm_cards_conversation                    (account_id,conversation_id,status,id)
#  idx_crm_cards_entered_stage                   (account_id,entered_stage_at)
#  idx_crm_cards_inbox_owner                     (account_id,inbox_id,owner_id)
#  idx_crm_cards_last_message                    (account_id,last_message_at)
#  idx_crm_cards_next_follow_up                  (account_id,next_follow_up_at)
#  idx_crm_cards_owner                           (account_id,owner_id,status,id)
#  idx_crm_cards_status_created                  (account_id,status,created_at)
#  idx_crm_cards_title_trgm                      (lower((title)::text) gin_trgm_ops) USING gin
#  idx_crm_cards_visible_inbox                   (account_id,inbox_id,status,id)
#  index_crm_cards_on_account_id                 (account_id)
#  index_crm_cards_on_account_score_updated      (account_id,score,updated_at)
#  index_crm_cards_on_contact_id                 (contact_id)
#  index_crm_cards_on_conversation_id            (conversation_id)
#  index_crm_cards_on_inbox_id                   (inbox_id)
#  index_crm_cards_on_owner_id                   (owner_id)
#  index_crm_cards_on_pipeline_id                (pipeline_id)
#  index_crm_cards_on_pipeline_status_score      (pipeline_id,status,score)
#  index_crm_cards_on_stage_id                   (stage_id)
#  index_crm_cards_on_team_id                    (team_id)
#  uniq_crm_cards_external_id_per_account        (account_id,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (owner_id => users.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (stage_id => crm_pipeline_stages.id)
#  fk_rails_...  (team_id => teams.id)
#
class Crm::Card < ApplicationRecord
  self.table_name = 'crm_cards'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :stage, class_name: 'Crm::PipelineStage'
  belongs_to :contact, optional: true
  belongs_to :primary_conversation, class_name: 'Conversation', foreign_key: :conversation_id, optional: true, inverse_of: false
  belongs_to :inbox, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :team, optional: true

  has_many :card_conversations, class_name: 'Crm::CardConversation', dependent: :destroy, inverse_of: :card
  has_many :linked_conversations, through: :card_conversations, source: :conversation
  has_many :activities, class_name: 'Crm::Activity', dependent: :destroy, inverse_of: :card
  has_many :follow_ups, class_name: 'Crm::FollowUp', dependent: :destroy, inverse_of: :card
  has_many :ai_stage_suggestions, class_name: 'Crm::AiStageSuggestion', dependent: :destroy, inverse_of: :card

  # Memória das IAs (#1601): campo editado à mão e pedido encerrado.
  include Crm::CardMemoria

  enum status: { open: 0, won: 1, lost: 2, archived: 3, resolved: 4, cancelled: 5 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  # Arquivar não desfaz o fechamento: o card ganho, perdido, resolvido ou cancelado que é arquivado guarda aqui o
  # desfecho que tinha, e o closed_at fica. Números, metas e relatórios continuam contando (scope com_desfecho), e
  # reabrir o arquivado devolve esse desfecho com a data de antes (Crm::Cards::Closer). Só o próprio card escreve a chave.
  DESFECHO_ARQUIVADO = 'desfecho_arquivado'.freeze

  before_validation :ensure_activity_defaults
  before_save :manter_desfecho_arquivado
  before_save :sync_closed_at
  # Ganho só existe em funil que conta como venda: quem comprou vira cliente (#1144). No modelo, para valer em todo
  # caminho que grava o ganho (fechar, criar já ganho, lote, automação).
  after_save :promote_contact_to_customer, if: -> { saved_change_to_status?(to: 'won') && contact.present? }
  # Acesso por funil (#1148): funil, status, conversa principal e dono (#1652, "Só as suas") do card decidem quem vê a
  # conversa.
  after_commit :invalidate_funnel_counts, if: -> { saved_changes.keys.intersect?(%w[pipeline_id status conversation_id owner_id]) }
  # Agente de IA responsável por caixa + funil (#1447): o card em atendimento mudou de funil.
  after_commit :sync_responsible_agent, on: :update, if: :saved_change_to_pipeline_id?
  # Decisão "a" (#1606): o card mudou de funil; a pessoa com a conversa pode não cuidar do funil novo.
  after_commit :sugerir_repasse, on: :update, if: :saved_change_to_pipeline_id?

  validates :title, presence: true
  validates :currency, presence: true
  validates :external_id, length: { maximum: 255 }, uniqueness: { scope: :account_id }, allow_blank: true
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :metadata, jsonb_attributes_length: true
  validates :custom_attributes, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account
  validate :stage_must_belong_to_pipeline
  validate :outcome_must_match_pipeline

  scope :active, -> { where(status: statuses[:open]) }
  scope :standalone, -> { where(contact_id: nil, conversation_id: nil, inbox_id: nil) }
  scope :linked, -> { where('contact_id IS NOT NULL OR conversation_id IS NOT NULL OR inbox_id IS NOT NULL') }
  # Os cards com estes desfechos, inclusive os arquivados depois de fechados com eles (DESFECHO_ARQUIVADO).
  scope :com_desfecho, lambda { |*desfechos|
    nomes = desfechos.flatten.map(&:to_s)
    where(status: nomes).or(where(status: :archived).where("crm_cards.metadata->>'#{DESFECHO_ARQUIVADO}' IN (?)", nomes))
  }

  # O mesmo filtro em SQL puro, para consulta montada à mão (um bind: o nome do desfecho).
  def self.desfecho_sql
    "(crm_cards.status = #{statuses[:archived]} AND crm_cards.metadata->>'#{DESFECHO_ARQUIVADO}' = ?)"
  end

  # O desfecho que conta: o status ou, no arquivado depois de fechado, o desfecho guardado.
  def self.desfecho_de(status, desfecho_arquivado)
    status.to_s == 'archived' && desfecho_arquivado.present? ? desfecho_arquivado : status.to_s
  end

  def desfecho_arquivado
    archived? ? metadata.to_h[DESFECHO_ARQUIVADO] : nil
  end

  # Donos que saíram da conta (#2095), entre os ids dados. O validate_owner_account recusa gravar o card com um deles.
  # Quem sai passa a ter os cards soltos (Agents::DestroyJob); os de antes disso ainda guardam o id, e o restaurar e o
  # arquivar do funil soltam o dono ao gravar, em vez de travar.
  def self.donos_fora_da_conta(account_id, owner_ids)
    ids = owner_ids.compact.uniq
    return Set.new if ids.empty?

    Set.new(ids) - AccountUser.where(account_id: account_id, user_id: ids).pluck(:user_id)
  end

  def dono_saiu_da_conta?
    self.class.donos_fora_da_conta(account_id, [owner_id]).any?
  end

  def standalone?
    contact_id.blank? && conversation_id.blank? && inbox_id.blank?
  end

  # A CONVERSA EM QUE O CLIENTE ESTÁ AGORA, que não é a primária depois da primeira.
  #
  # O card é do contato e a primária fica fixada na conversa que o criou; toda conversa nova
  # entra como secundária. Quem precisa agir sobre o atendimento — passar para uma pessoa, por
  # exemplo — tem de agir aqui, senão mexe numa conversa antiga que ninguém está lendo, enquanto
  # o cliente espera na conversa viva (issue #553).
  #
  # A MAIS RECENTE ENTRE AS QUE AINDA ESTÃO DE PÉ, aberta ou pendente. Quem decide é a atividade,
  # não o estado: `pending` é a conversa que o bot ainda segura, e preferir `open` faria uma
  # conversa antiga que ninguém resolveu ganhar daquela em que o cliente está falando agora.
  # O `id` desempata, e não é enfeite: duas conversas do mesmo contato podem ter o mesmo
  # `last_activity_at`, e sem ele a escolha mudava de uma execução para outra. Sem nenhuma de pé,
  # a primária é o melhor palpite que existe.
  def conversa_em_atendimento
    linked_conversations
      .where(status: [Conversation.statuses[:open], Conversation.statuses[:pending]])
      .order(last_activity_at: :desc, id: :desc)
      .first || primary_conversation
  end

  # Real-time "responsible" for the card, derived (never a stored snapshot):
  #   1. human assignee of the linked conversation (or owner for standalone) -> agent
  #   2. otherwise the active AgentBot connected to the inbox -> bot
  #   3. otherwise nobody
  def responsible_descriptor
    agent = primary_conversation ? primary_conversation.assignee : owner
    return { type: 'agent', id: agent.id, name: agent.name } if agent.present?

    bot = responsible_agent_bot
    return { type: 'bot', id: bot.id, name: bot.name } if bot.present?

    nil
  end

  # Quem carrega o card agora (#1151): o dono; sem dono (card antigo, dono tirado em lote), o que o quadro mostra — a
  # pessoa da conversa, o robô da caixa ou ninguém. Carga de trabalho e o registro do fechamento (#1876) leem daqui.
  def current_responsible
    return { type: 'agent', id: owner.id, name: owner.name } if owner.present?

    responsible_descriptor
  end

  # O robô atribuído à conversa (#1377); sem ele, o robô ativo da caixa.
  def responsible_agent_bot
    conversation_bot = primary_conversation&.ai_assignee
    return conversation_bot if conversation_bot.is_a?(AgentBot)

    active_inbox_bot(primary_conversation&.inbox || inbox)
  end

  private

  def active_inbox_bot(resolved_inbox)
    return if resolved_inbox.blank?

    # Pelo agent_bot_inbox, e não pelo has_one :through: assim o preload de agent_bot_inbox: :agent_bot vale (#2283).
    bot_inbox = resolved_inbox.agent_bot_inbox
    bot_inbox&.active? ? bot_inbox.agent_bot : nil
  end

  def sugerir_repasse
    Crm::RepassePorCardJob.perform_later(id)
  end

  def sync_responsible_agent
    Crm::Ai::ResponsibleAgentSync.agendar_para_card(self, motivo: Crm::Ai::ResponsibleAgentSync::PIPELINE)
  end

  def invalidate_funnel_counts
    return unless Crm::Access::AccountFlag.any?(account_id)
    return if owner_change_only? && !Crm::InboxAgentAccess.exists?(account_id: account_id, only_own: true)

    previous_conversation_id = saved_changes['conversation_id']&.first
    conversation_ids = [conversation_id, previous_conversation_id] + card_conversations.pluck(:conversation_id)
    Crm::Access::CountInvalidation.card_changed!(account_id, conversation_ids)
  end

  # O dono só decide quem vê em "Só as suas" (#1652): sem ninguém nesse modo na conta, trocar o dono não muda a visão.
  def owner_change_only?
    !saved_changes.keys.intersect?(%w[pipeline_id status conversation_id])
  end

  def ensure_activity_defaults
    self.entered_stage_at ||= Time.current
    self.last_activity_at ||= Time.current
  end

  # closed_at is the source of truth for win/lost + cycle-time reports.
  # It must reflect the explicit close decision, never updated_at.
  # Arquivar guarda o desfecho e mantém a data; sair do arquivo volta a ler o desfecho guardado, e voltar a ele é o
  # mesmo fechamento, não um novo.
  def sync_closed_at
    return unless will_save_change_to_status?
    return arquivar_desfecho if archived?

    anterior = status_in_database == 'archived' ? metadata_in_database.to_h[DESFECHO_ARQUIVADO] : status_in_database
    self.metadata = metadata.to_h.except(DESFECHO_ARQUIVADO)
    return if anterior == status
    # Ganho -> resolvido ao mudar de funil é o mesmo fechamento, não um novo (#1144).
    return if Crm::Cards::Outcome.equivalent?(anterior, status)

    self.closed_at = Crm::Cards::Outcome::CLOSED_STATUSES.include?(status) ? Time.current : nil
  end

  def arquivar_desfecho
    anterior = status_in_database
    if Crm::Cards::Outcome::CLOSED_STATUSES.include?(anterior)
      self.metadata = metadata.to_h.merge(DESFECHO_ARQUIVADO => anterior)
    else
      self.metadata = metadata.to_h.except(DESFECHO_ARQUIVADO)
      self.closed_at = nil
    end
  end

  # A chave do desfecho só muda junto com o status: edição de metadata (PATCH, upsert) não cria nem troca venda. O
  # arquivado que muda de funil leva o desfecho como o card fechado leva o status (Crm::Cards::Mover, #1144 e #1498).
  def manter_desfecho_arquivado
    return if will_save_change_to_status?

    guardado = metadata_in_database.to_h[DESFECHO_ARQUIVADO]
    guardado = desfecho_no_funil_novo(guardado) if guardado && will_save_change_to_pipeline_id?
    return if metadata.to_h[DESFECHO_ARQUIVADO] == guardado

    self.metadata = guardado ? metadata.to_h.merge(DESFECHO_ARQUIVADO => guardado) : metadata.to_h.except(DESFECHO_ARQUIVADO)
  end

  # Atendimento fechado que vai para um funil de Vender entra Aberto: sem desfecho e sem data.
  def desfecho_no_funil_novo(guardado)
    novo = Crm::Cards::Outcome.status_after_move(pipeline, guardado)
    return novo if Crm::Cards::Outcome::CLOSED_STATUSES.include?(novo)

    self.closed_at = nil
    nil
  end

  # Ganho/perdido só em funil que conta como venda; resolvido/cancelado só nos outros (#1144). Checado só quando o status
  # muda: um card ganho antes de o funil deixar de contar como venda continua editável.
  def promote_contact_to_customer
    contact.become_customer!
  end

  def outcome_must_match_pipeline
    return if pipeline.blank? || !will_save_change_to_status?
    return if Crm::Cards::Outcome.status_for(pipeline, status) == status

    errors.add(:status, "#{status} is not a closing result of this pipeline")
  end

  def stage_must_belong_to_pipeline
    return if stage.blank? || pipeline.blank?
    return if stage.pipeline_id == pipeline_id

    errors.add(:stage, 'must belong to the selected pipeline')
  end

  def linked_records_must_belong_to_account
    validate_same_account(:pipeline)
    validate_same_account(:stage)
    validate_same_account(:contact)
    validate_same_account(:primary_conversation)
    validate_same_account(:inbox)
    validate_same_account(:team)
    validate_owner_account
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end

  def validate_owner_account
    return if owner.blank? || account_id.blank?
    return if owner.account_users.exists?(account_id: account_id)

    errors.add(:owner, 'must belong to the same account')
  end
end
