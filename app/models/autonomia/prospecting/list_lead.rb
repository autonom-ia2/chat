# == Schema Information
#
# Table name: autonomia_prospecting_list_leads
#
#  id               :bigint           not null, primary key
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  prospect_lead_id :bigint           not null
#  prospect_list_id :bigint           not null
#
# Indexes
#
#  idx_autonomia_prospecting_list_leads_lead_id          (prospect_lead_id)
#  idx_autonomia_prospecting_list_leads_list_id          (prospect_list_id)
#  idx_autonomia_prospecting_list_leads_unique           (prospect_list_id,prospect_lead_id) UNIQUE
#  index_autonomia_prospecting_list_leads_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (prospect_lead_id => autonomia_prospecting_leads.id) ON DELETE => cascade
#  fk_rails_...  (prospect_list_id => autonomia_prospecting_lists.id) ON DELETE => cascade
#
class Autonomia::Prospecting::ListLead < ApplicationRecord
  self.table_name = 'autonomia_prospecting_list_leads'

  belongs_to :account
  belongs_to :list, class_name: 'Autonomia::Prospecting::List', foreign_key: :prospect_list_id, inverse_of: :list_leads
  belongs_to :lead, class_name: 'Autonomia::Prospecting::Lead', foreign_key: :prospect_lead_id, inverse_of: :list_leads

  validates :prospect_lead_id, uniqueness: { scope: :prospect_list_id }
  validate :records_must_belong_to_account

  private

  def records_must_belong_to_account
    validate_same_account(:list)
    validate_same_account(:lead)
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
