# == Schema Information
#
# Table name: campaign_import_labels
#
#  id                 :bigint           not null, primary key
#  applied_count      :integer          default(0), not null
#  batch_index        :integer
#  kind               :integer          default("base"), not null
#  planned_count      :integer          default(0), not null
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  campaign_import_id :bigint           not null
#  label_id           :bigint
#
# Indexes
#
#  idx_campaign_import_labels_on_import_and_title      (campaign_import_id,title) UNIQUE
#  index_campaign_import_labels_on_campaign_import_id  (campaign_import_id)
#  index_campaign_import_labels_on_label_id            (label_id)
#
class CampaignImportLabel < ApplicationRecord
  belongs_to :campaign_import
  belongs_to :label, optional: true

  enum kind: { base: 0, batch: 1 }, _prefix: true

  validates :title, presence: true
end
