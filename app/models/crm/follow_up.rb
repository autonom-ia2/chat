# == Schema Information
#
# Table name: crm_follow_ups
#
#  id              :bigint           not null, primary key
#  automation_mode :integer          default("reminder_only"), not null
#  canceled_at     :datetime
#  completed_at    :datetime
#  description     :text
#  due_at          :datetime         not null
#  follow_up_type  :integer          default("task"), not null
#  metadata        :jsonb            not null
#  status          :integer          default("pending"), not null
#  timezone        :string           default("UTC"), not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  assignee_id     :bigint
#  card_id         :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  created_by_id   :bigint
#  inbox_id        :bigint
#
# Indexes
#
#  idx_crm_followups_assignee_due           (account_id,assignee_id,due_at,status)
#  idx_crm_followups_card                   (account_id,card_id)
#  idx_crm_followups_conversation           (account_id,conversation_id)
#  idx_crm_followups_due_processor          (status,due_at,id)
#  idx_crm_followups_status_due             (account_id,status,due_at)
#  index_crm_follow_ups_on_account_id       (account_id)
#  index_crm_follow_ups_on_assignee_id      (assignee_id)
#  index_crm_follow_ups_on_card_id          (card_id)
#  index_crm_follow_ups_on_contact_id       (contact_id)
#  index_crm_follow_ups_on_conversation_id  (conversation_id)
#  index_crm_follow_ups_on_created_by_id    (created_by_id)
#  index_crm_follow_ups_on_inbox_id         (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::FollowUp < ApplicationRecord
  self.table_name = 'crm_follow_ups'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  belongs_to :inbox, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  enum follow_up_type: { task: 0, message: 1, call: 2, meeting: 3, note: 4 }
  enum status: { pending: 0, done: 1, canceled: 2, overdue: 3 }
  enum automation_mode: { reminder_only: 0, snooze_conversation: 1, auto_send_message: 2 }

  validates :title, :due_at, :timezone, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account
  validate :snooze_requires_conversation
  validate :auto_send_requirements

  scope :active, -> { where(status: [statuses[:pending], statuses[:overdue]]) }
  scope :due, ->(time = Time.current) { pending.where(due_at: ..time) }

  private

  def snooze_requires_conversation
    return unless snooze_conversation?
    return if conversation_id.present?

    errors.add(:conversation, 'is required for snooze follow-ups')
  end

  def auto_send_requirements
    return unless auto_send_message?

    Crm::FollowUps::AutoSendValidator.new(self).validate
  end

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:conversation)
    validate_same_account(:contact)
    validate_same_account(:inbox)
    validate_assignee_account
    validate_created_by_account
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end

  def validate_assignee_account
    return if assignee.blank? || account_id.blank?
    return if assignee.account_users.exists?(account_id: account_id)

    errors.add(:assignee, 'must belong to the same account')
  end

  def validate_created_by_account
    return if created_by.blank? || account_id.blank?
    return if created_by.account_users.exists?(account_id: account_id)

    errors.add(:created_by, 'must belong to the same account')
  end
end
