class EmailCampaignImportIssue < ApplicationRecord
  belongs_to :email_campaign
  belongs_to :email_campaign_import, optional: true

  scope :for_account, ->(account) { joins(:email_campaign).where(email_campaigns: { account_id: account.id }) }
  validates :row_number, numericality: { only_integer: true, greater_than: 0 }
  validates :reason_code, presence: true
  validates :raw_address, :suggestion, length: { maximum: 320 }
  validate :same_campaign

  # Future report/export callers must start from for_account(account) or a scoped campaign.
  def export_attributes
    attributes.slice('row_number', 'raw_address', 'reason_code', 'suggestion').transform_values do |value|
      CampaignImports::CsvSanitizer.safe_cell(value)
    end
  end

  private

  def same_campaign
    return unless email_campaign_import && email_campaign_import.email_campaign_id != email_campaign_id

    errors.add(:email_campaign_import, 'must match campaign')
  end
end
