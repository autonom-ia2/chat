# == Schema Information
#
# Table name: whatsapp_api_campaign_recipients
#
#  id                       :bigint           not null, primary key
#  attempts                 :integer          default(0), not null
#  cancelled_at             :datetime
#  failed_at                :datetime
#  last_error_message       :text
#  phone_hash               :string
#  phone_mask               :string
#  rendered_body_sha256     :string
#  sent_at                  :datetime
#  started_at               :datetime
#  status                   :integer          default("pending"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  contact_id               :bigint           not null
#  conversation_id          :bigint
#  inbox_id                 :bigint
#  message_id               :bigint
#  provider_message_id      :string
#  whatsapp_api_campaign_id :bigint           not null
#
# Indexes
#
#  idx_wa_api_recipients_active_phone_hash                    (whatsapp_api_campaign_id,phone_hash) UNIQUE WHERE ((phone_hash IS NOT NULL) AND (status = ANY (ARRAY[0, 1, 2])))
#  idx_wa_api_recipients_campaign_contact                     (whatsapp_api_campaign_id,contact_id) UNIQUE
#  idx_wa_api_recipients_campaign_id                          (whatsapp_api_campaign_id)
#  idx_wa_api_recipients_campaign_message                     (whatsapp_api_campaign_id,message_id) UNIQUE WHERE (message_id IS NOT NULL)
#  idx_wa_api_recipients_campaign_status                      (whatsapp_api_campaign_id,status)
#  idx_wa_api_recipients_inbox_status                         (inbox_id,status,created_at)
#  index_whatsapp_api_campaign_recipients_on_account_id       (account_id)
#  index_whatsapp_api_campaign_recipients_on_contact_id       (contact_id)
#  index_whatsapp_api_campaign_recipients_on_conversation_id  (conversation_id)
#  index_whatsapp_api_campaign_recipients_on_inbox_id         (inbox_id)
#  index_whatsapp_api_campaign_recipients_on_message_id       (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (whatsapp_api_campaign_id => whatsapp_api_campaigns.id)
#
class WhatsappApiCampaignRecipient < ApplicationRecord
  belongs_to :whatsapp_api_campaign
  belongs_to :account
  belongs_to :inbox
  belongs_to :contact
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  enum status: {
    pending: 0,
    sending: 1,
    sent: 2,
    failed: 3,
    cancelled: 4
  }

  validates :account_id, :inbox_id, :contact_id, presence: true
  validate :associations_must_match_campaign

  def mark_failed!(message)
    update!(
      status: :failed,
      last_error_message: message.to_s.truncate(500),
      failed_at: Time.current
    )
  end

  private

  def associations_must_match_campaign
    return unless whatsapp_api_campaign

    errors.add(:account_id, 'must match campaign') if account_id != whatsapp_api_campaign.account_id
    errors.add(:inbox_id, 'must match campaign') if inbox_id != whatsapp_api_campaign.inbox_id
  end
end
