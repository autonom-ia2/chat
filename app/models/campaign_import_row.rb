# == Schema Information
#
# Table name: campaign_import_rows
#
#  id                    :bigint           not null, primary key
#  batch_index           :integer
#  error_messages        :jsonb            not null
#  labels_applied        :jsonb            not null
#  normalized_name       :string
#  normalized_phone_hash :string
#  raw_name              :string
#  raw_phone_masked      :string
#  row_number            :integer          not null
#  status                :integer          default("pending"), not null
#  was_existing_contact  :boolean          default(FALSE), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  campaign_import_id    :bigint           not null
#  contact_id            :bigint
#
# Indexes
#
#  idx_campaign_import_rows_on_import_and_row_number            (campaign_import_id,row_number) UNIQUE
#  index_campaign_import_rows_on_campaign_import_id             (campaign_import_id)
#  index_campaign_import_rows_on_campaign_import_id_and_status  (campaign_import_id,status)
#  index_campaign_import_rows_on_contact_id                     (contact_id)
#  index_campaign_import_rows_on_normalized_phone_hash          (normalized_phone_hash)
#
class CampaignImportRow < ApplicationRecord
  belongs_to :campaign_import
  belongs_to :contact, optional: true

  enum status: {
    pending: 0,
    valid: 1,
    invalid: 2,
    imported: 3,
    import_failed: 4,
    labels_undone: 5,
    undo_failed: 6
  }, _prefix: true

  validates :row_number, presence: true
end
