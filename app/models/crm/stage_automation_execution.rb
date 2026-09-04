# == Schema Information
#
# Table name: crm_stage_automation_executions
#
#  id                  :bigint           not null, primary key
#  completed_at        :datetime
#  error_message       :text
#  metadata            :jsonb            not null
#  status              :integer          default("running"), not null
#  trigger_token       :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  card_id             :bigint           not null
#  stage_automation_id :bigint           not null
#
# Indexes
#
#  idx_crm_stage_automation_executions_unique                    (card_id,stage_automation_id,trigger_token) UNIQUE
#  index_crm_stage_automation_executions_on_account_id           (account_id)
#  index_crm_stage_automation_executions_on_card_id              (card_id)
#  index_crm_stage_automation_executions_on_stage_automation_id  (stage_automation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (stage_automation_id => crm_stage_automations.id)
#
class Crm::StageAutomationExecution < ApplicationRecord
  self.table_name = 'crm_stage_automation_executions'

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card'
  belongs_to :stage_automation, class_name: 'Crm::StageAutomation'

  enum status: { running: 0, completed: 1, failed: 2 }

  validates :trigger_token, presence: true
  validates :metadata, jsonb_attributes_length: true
end
