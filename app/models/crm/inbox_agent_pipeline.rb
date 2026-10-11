# Um funil liberado para a pessoa na caixa, quando ela não vê todos (#1148).
class Crm::InboxAgentPipeline < ApplicationRecord
  self.table_name = 'crm_inbox_agent_pipelines'

  belongs_to :account
  belongs_to :access, class_name: 'Crm::InboxAgentAccess', inverse_of: :agent_pipelines
  belongs_to :pipeline, class_name: 'Crm::Pipeline'

  validates :pipeline_id, uniqueness: { scope: :access_id }
  validate :pipeline_must_belong_to_account
  after_commit -> { Crm::Access::CountInvalidation.access_changed!(account_id, access&.user_id) }

  private

  def pipeline_must_belong_to_account
    errors.add(:pipeline_id, 'must belong to the account') if pipeline && pipeline.account_id != account_id
    errors.add(:access_id, 'must belong to the account') if access && access.account_id != account_id
  end
end
