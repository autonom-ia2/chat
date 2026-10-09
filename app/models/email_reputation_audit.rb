# No application update/delete path. Snapshot includes the policy and actor at the transition.
class EmailReputationAudit < ApplicationRecord
  belongs_to :account, optional: true
  validates :action, presence: true

  def readonly?
    persisted?
  end
end
