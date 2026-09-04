# == Schema Information
#
# Table name: crm_activities
#
#  id              :bigint           not null, primary key
#  actor_type      :string
#  event_type      :string           not null
#  payload         :jsonb            not null
#  created_at      :datetime         not null
#  account_id      :bigint           not null
#  actor_id        :bigint
#  card_id         :bigint           not null
#  conversation_id :bigint
#
# Indexes
#
#  idx_crm_activities_card_time             (account_id,card_id,created_at)
#  idx_crm_activities_event_time            (account_id,event_type,created_at)
#  index_crm_activities_on_account_id       (account_id)
#  index_crm_activities_on_card_id          (card_id)
#  index_crm_activities_on_conversation_id  (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#
class Crm::Activity < ApplicationRecord
  self.table_name = 'crm_activities'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation, optional: true

  validates :event_type, presence: true
  validates :payload, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account

  after_commit :emit_webhook_event, on: :create

  private

  # Bridge CRM lifecycle activities to outbound account webhooks.
  # Runs AFTER the mover/closer/creator transaction commits (plan B2) and hands
  # IDS ONLY to the Emitter — never AR objects — so the listener reloads by id.
  def emit_webhook_event
    Crm::Webhooks::Emitter.emit(
      account_id: account_id,
      card_id: card_id,
      activity_id: id,
      event_type: event_type,
      changed_attributes: payload
    )
  end

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:conversation)
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
