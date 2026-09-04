# == Schema Information
#
# Table name: whatsapp_api_message_templates
#
#  id            :bigint           not null, primary key
#  archived_at   :datetime
#  body          :text             not null
#  name          :string           not null
#  variables     :jsonb            not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint           not null
#  inbox_id      :bigint
#  updated_by_id :bigint
#
# Indexes
#
#  idx_whatsapp_api_templates_active_name                 (account_id,inbox_id,name) UNIQUE WHERE (archived_at IS NULL)
#  idx_whatsapp_api_templates_inbox                       (account_id,inbox_id,archived_at)
#  index_whatsapp_api_message_templates_on_account_id     (account_id)
#  index_whatsapp_api_message_templates_on_created_by_id  (created_by_id)
#  index_whatsapp_api_message_templates_on_inbox_id       (inbox_id)
#  index_whatsapp_api_message_templates_on_updated_by_id  (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (updated_by_id => users.id)
#
class WhatsappApiMessageTemplate < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User'
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :body, presence: true, length: { maximum: 150_000 }
  validate :inbox_must_belong_to_account
  validate :inbox_must_be_whatsapp_api_campaign_channel
  validate :variables_must_be_supported

  before_validation :normalize_name
  before_validation :set_variables

  scope :active, -> { where(archived_at: nil) }
  scope :for_inbox, ->(inbox_id) { where(inbox_id: inbox_id) }

  def archived?
    archived_at.present?
  end

  def archive!
    update!(archived_at: Time.current)
  end

  private

  def normalize_name
    self.name = name.to_s.strip
  end

  def set_variables
    self.variables = WhatsappApiCampaigns::TemplateRenderer.variables_in(body)
  end

  def inbox_must_belong_to_account
    return unless inbox
    return if inbox.account_id == account_id

    errors.add(:inbox_id, 'must belong to the same account')
  end

  def inbox_must_be_whatsapp_api_campaign_channel
    return unless inbox
    return if inbox.api? && inbox.channel.whatsapp_api_campaign_channel?

    errors.add(:inbox_id, 'must be an API inbox marked for WhatsApp API campaigns')
  end

  def variables_must_be_supported
    unsupported = WhatsappApiCampaigns::TemplateRenderer.unsupported_variables_in(body)
    return if unsupported.blank?

    errors.add(:body, "has unsupported variables: #{unsupported.join(', ')}")
  end
end
