# == Schema Information
#
# Table name: crm_pipeline_stages
#
#  id                  :bigint           not null, primary key
#  color               :string
#  description         :text
#  is_lost_stage       :boolean          default(FALSE), not null
#  is_won_stage        :boolean          default(FALSE), not null
#  metadata            :jsonb            not null
#  name                :string           not null
#  position            :integer          default(0), not null
#  sla_seconds         :integer
#  sla_warning_seconds :integer
#  win_probability     :integer          default(0), not null
#  wip_limit           :integer
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  pipeline_id         :bigint           not null
#
# Indexes
#
#  idx_crm_stages_account_pipeline_position                 (account_id,pipeline_id,position)
#  index_crm_pipeline_stages_on_account_id                  (account_id)
#  index_crm_pipeline_stages_on_account_id_and_pipeline_id  (account_id,pipeline_id)
#  index_crm_pipeline_stages_on_pipeline_id                 (pipeline_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (pipeline_id => crm_pipelines.id)
#
class Crm::PipelineStage < ApplicationRecord
  self.table_name = 'crm_pipeline_stages'

  belongs_to :account
  belongs_to :pipeline, class_name: 'Crm::Pipeline'

  has_many :cards, class_name: 'Crm::Card', foreign_key: :stage_id, dependent: :restrict_with_error, inverse_of: :stage
  has_many :stage_automations, class_name: 'Crm::StageAutomation', foreign_key: :stage_id, dependent: :destroy
  # AI suggestion rows are dangling history once the stage is gone (the columns are NOT NULL, so they
  # cannot be nullified). Cascade-delete them so a stage the AI has touched stays deletable.
  has_many :ai_suggestions_from, class_name: 'Crm::AiStageSuggestion', foreign_key: :from_stage_id, dependent: :delete_all, inverse_of: :from_stage
  has_many :ai_suggestions_to, class_name: 'Crm::AiStageSuggestion', foreign_key: :to_stage_id, dependent: :delete_all, inverse_of: :to_stage

  validates :name, presence: true
  validates :position, numericality: { only_integer: true }
  validates :win_probability, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :metadata, jsonb_attributes_length: true
  validate :pipeline_must_belong_to_account

  private

  def pipeline_must_belong_to_account
    return if pipeline.blank? || account_id.blank?
    return if pipeline.account_id == account_id

    errors.add(:pipeline, 'must belong to the same account')
  end
end
