# == Schema Information
#
# Table name: crm_pipeline_inboxes
#
#  id               :bigint           not null, primary key
#  auto_create_card :boolean          default(FALSE), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  created_by_id    :bigint
#  default_stage_id :bigint
#  inbox_id         :bigint
#  pipeline_id      :bigint           not null
#
# Indexes
#
#  idx_crm_pipeline_inboxes_unique                        (account_id,pipeline_id,inbox_id) UNIQUE
#  index_crm_pipeline_inboxes_on_account_id               (account_id)
#  index_crm_pipeline_inboxes_on_account_id_and_inbox_id  (account_id,inbox_id)
#  index_crm_pipeline_inboxes_on_created_by_id            (created_by_id)
#  index_crm_pipeline_inboxes_on_default_stage_id         (default_stage_id)
#  index_crm_pipeline_inboxes_on_inbox_id                 (inbox_id)
#  index_crm_pipeline_inboxes_on_pipeline_id              (pipeline_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (default_stage_id => crm_pipeline_stages.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#
class Crm::PipelineInbox < ApplicationRecord
  self.table_name = 'crm_pipeline_inboxes'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :inbox
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  validates :inbox_id, uniqueness: { scope: [:account_id, :pipeline_id] }
  validate :linked_records_must_belong_to_account
  validate :default_stage_must_belong_to_pipeline

  private

  def linked_records_must_belong_to_account
    validate_same_account(:pipeline)
    validate_same_account(:inbox)
    validate_same_account(:default_stage)
  end

  def default_stage_must_belong_to_pipeline
    return if default_stage.blank? || pipeline.blank?
    return if default_stage.pipeline_id == pipeline_id

    errors.add(:default_stage, 'must belong to the selected pipeline')
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
