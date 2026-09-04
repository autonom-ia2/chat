# == Schema Information
#
# Table name: campaign_imports
#
#  id                              :bigint           not null, primary key
#  base_label                      :string
#  batch_count                     :integer          default(0), not null
#  campaign_name                   :string
#  campaign_slug                   :string
#  completed_at                    :datetime
#  confirmed_at                    :datetime
#  duplicate_file_rows             :integer          default(0), not null
#  existing_contacts_count         :integer          default(0), not null
#  existing_contacts_updated_count :integer          default(0), not null
#  failed_at                       :datetime
#  failed_contacts_count           :integer          default(0), not null
#  failed_records                  :integer          default(0), not null
#  import_finished_at              :datetime
#  import_started_at               :datetime
#  imported_contacts_count         :integer          default(0), not null
#  invalid_rows                    :integer          default(0), not null
#  labels_payload                  :jsonb            not null
#  mode                            :string
#  new_contacts_count              :integer          default(0), not null
#  new_contacts_estimate           :integer          default(0), not null
#  options                         :jsonb            not null
#  processed_records               :integer          default(0), not null
#  queued_at                       :datetime
#  source_byte_size                :bigint
#  source_content_type             :string
#  source_filename                 :string
#  source_format                   :string
#  started_at                      :datetime
#  status                          :integer          default("uploaded"), not null
#  total_rows                      :integer          default(0), not null
#  undo_completed_at               :datetime
#  undo_finished_at                :datetime
#  undo_started_at                 :datetime
#  undo_status                     :integer          default("pending"), not null
#  valid_rows                      :integer          default(0), not null
#  validated_at                    :datetime
#  validation_summary              :jsonb            not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  account_id                      :bigint           not null
#  data_import_id                  :bigint
#  user_id                         :bigint           not null
#
# Indexes
#
#  index_campaign_imports_on_account_id                    (account_id)
#  index_campaign_imports_on_account_id_and_campaign_slug  (account_id,campaign_slug)
#  index_campaign_imports_on_account_id_and_created_at     (account_id,created_at)
#  index_campaign_imports_on_account_id_and_status         (account_id,status)
#  index_campaign_imports_on_data_import_id                (data_import_id)
#  index_campaign_imports_on_user_id                       (user_id)
#
class CampaignImport < ApplicationRecord
  DELETABLE_BEFORE_IMPORT_STATUSES = %w[uploaded validation_failed ready_to_confirm failed cancelled expired].freeze

  belongs_to :account
  belongs_to :user
  belongs_to :data_import, optional: true

  has_many :campaign_import_rows, dependent: :destroy
  has_many :campaign_import_labels, dependent: :destroy

  has_one_attached :original_file
  has_one_attached :normalized_csv
  has_one_attached :error_csv
  has_one_attached :report_csv

  enum status: {
    uploaded: 0,
    validating: 1,
    validation_failed: 2,
    ready_to_confirm: 3,
    confirmed: 4,
    queued: 5,
    importing: 6,
    completed: 7,
    completed_with_failures: 8,
    failed: 9,
    cancelled: 10,
    expired: 11,
    undoing_labels: 12,
    labels_undone: 13,
    undo_failed: 14
  }

  enum undo_status: {
    pending: 0,
    processing: 1,
    completed: 2,
    failed: 3
  }, _prefix: true

  validates :account_id, :user_id, presence: true
  validates :mode, inclusion: { in: %w[single_label batches] }, allow_blank: true

  def downloadable_error_csv?
    error_csv.attached?
  end

  def downloadable_report_csv?
    report_csv.attached?
  end

  def deletable_before_import?
    DELETABLE_BEFORE_IMPORT_STATUSES.include?(status) &&
      imported_contacts_count.zero? &&
      campaign_import_rows.where.not(contact_id: nil).none?
  end

  def base_label
    labels = campaign_import_labels.loaded? ? campaign_import_labels : campaign_import_labels.kind_base
    labels.find { |label| label.kind_base? }&.title
  end
end
