# == Schema Information
#
# Table name: crm_stage_automations
#
#  id            :bigint           not null, primary key
#  description   :text
#  enabled       :boolean          default(TRUE), not null
#  metadata      :jsonb            not null
#  name          :string           not null
#  position      :integer          default(0), not null
#  trigger_event :integer          default("on_enter"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#  pipeline_id   :bigint           not null
#  stage_id      :bigint           not null
#
# Indexes
#
#  idx_crm_stage_automations_stage_trigger       (account_id,stage_id,trigger_event,position)
#  index_crm_stage_automations_on_account_id     (account_id)
#  index_crm_stage_automations_on_created_by_id  (created_by_id)
#  index_crm_stage_automations_on_pipeline_id    (pipeline_id)
#  index_crm_stage_automations_on_stage_id       (stage_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#  fk_rails_...  (stage_id => crm_pipeline_stages.id)
#
class Crm::StageAutomation < ApplicationRecord
  self.table_name = 'crm_stage_automations'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :stage, class_name: 'Crm::PipelineStage'
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :steps, class_name: 'Crm::StageAutomationStep', foreign_key: :stage_automation_id,
                   dependent: :destroy, inverse_of: :stage_automation

  enum trigger_event: { on_enter: 0, on_exit: 1 }

  validates :name, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :metadata, jsonb_attributes_length: true
  validate :stage_must_belong_to_pipeline_and_account

  scope :enabled, -> { where(enabled: true) }
  scope :ordered, -> { order(:position, :id) }

  private

  def stage_must_belong_to_pipeline_and_account
    return if stage.blank? || pipeline.blank? || account_id.blank?

    errors.add(:stage, 'must belong to the selected pipeline') if stage.pipeline_id != pipeline_id
    errors.add(:pipeline, 'must belong to the same account') if pipeline.account_id != account_id
    errors.add(:stage, 'must belong to the same account') if stage.account_id != account_id
  end
end
