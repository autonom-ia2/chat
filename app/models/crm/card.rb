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
#  idx_crm_cards_unique_open_conversation        (conversation_id) UNIQUE WHERE ((conversation_id IS NOT NULL) AND (status = 0))
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

  enum status: { open: 0, won: 1, lost: 2, archived: 3 }
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  before_validation :ensure_activity_defaults
  before_save :sync_closed_at

  validates :title, presence: true
  validates :currency, presence: true
  validates :external_id, length: { maximum: 255 }, uniqueness: { scope: :account_id }, allow_blank: true
  validates :value_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :metadata, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account
  validate :stage_must_belong_to_pipeline

  scope :active, -> { where(status: statuses[:open]) }
  scope :standalone, -> { where(contact_id: nil, conversation_id: nil, inbox_id: nil) }
  scope :linked, -> { where('contact_id IS NOT NULL OR conversation_id IS NOT NULL OR inbox_id IS NOT NULL') }

  def standalone?
    contact_id.blank? && conversation_id.blank? && inbox_id.blank?
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

  def responsible_agent_bot
    resolved_inbox = primary_conversation&.inbox || inbox
    return if resolved_inbox.blank?

    resolved_inbox.agent_bot_inbox&.active? ? resolved_inbox.agent_bot : nil
  end

  private

  def ensure_activity_defaults
    self.entered_stage_at ||= Time.current
    self.last_activity_at ||= Time.current
  end

  # closed_at is the source of truth for win/lost + cycle-time reports.
  # It must reflect the explicit close decision, never updated_at.
  def sync_closed_at
    return unless will_save_change_to_status?

    self.closed_at = (won? || lost?) ? Time.current : nil
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
