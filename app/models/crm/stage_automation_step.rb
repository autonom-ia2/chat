# == Schema Information
#
# Table name: crm_stage_automation_steps
#
#  id                  :bigint           not null, primary key
#  action_config       :jsonb            not null
#  action_type         :integer          default("create_follow_up"), not null
#  delay_seconds       :integer          default(0), not null
#  position            :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  stage_automation_id :bigint           not null
#
# Indexes
#
#  idx_crm_stage_automation_steps_order                     (stage_automation_id,position)
#  index_crm_stage_automation_steps_on_account_id           (account_id)
#  index_crm_stage_automation_steps_on_stage_automation_id  (stage_automation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (stage_automation_id => crm_stage_automations.id)
#
class Crm::StageAutomationStep < ApplicationRecord
  self.table_name = 'crm_stage_automation_steps'

  belongs_to :account
  belongs_to :stage_automation, class_name: 'Crm::StageAutomation', inverse_of: :steps

  enum action_type: { create_follow_up: 0, assign_owner: 1, move_stage: 2 }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :action_config, jsonb_attributes_length: true
  validate :action_config_must_be_valid

  scope :ordered, -> { order(:position, :id) }

  private

  def action_config_must_be_valid
    Crm::StageAutomations::StepConfigValidator.new(self).validate
  end
end
