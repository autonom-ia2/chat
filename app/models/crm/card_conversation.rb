# == Schema Information
#
# Table name: crm_card_conversations
#
#  id              :bigint           not null, primary key
#  is_primary      :boolean          default(FALSE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  card_id         :bigint           not null
#  conversation_id :bigint           not null
#  linked_by_id    :bigint
#
# Indexes
#
#  idx_crm_card_conversations_card                  (account_id,card_id)
#  idx_crm_card_conversations_conversation          (account_id,conversation_id)
#  idx_crm_card_conversations_unique                (account_id,card_id,conversation_id) UNIQUE
#  index_crm_card_conversations_on_account_id       (account_id)
#  index_crm_card_conversations_on_card_id          (card_id)
#  index_crm_card_conversations_on_conversation_id  (conversation_id)
#  index_crm_card_conversations_on_linked_by_id     (linked_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (linked_by_id => users.id)
#
class Crm::CardConversation < ApplicationRecord
  self.table_name = 'crm_card_conversations'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :conversation
  belongs_to :linked_by, class_name: 'User', optional: true

  validates :conversation_id, uniqueness: { scope: [:account_id, :card_id] }
  validate :linked_records_must_belong_to_account

  private

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
