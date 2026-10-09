# == Schema Information
#
# Table name: autonomia_prospecting_lists
#
#  id          :bigint           not null, primary key
#  description :text
#  metadata    :jsonb            not null
#  name        :string           not null
#  status      :integer          default("active"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  user_id     :bigint
#
# Indexes
#
#  index_autonomia_prospecting_lists_on_account_id           (account_id)
#  index_autonomia_prospecting_lists_on_account_id_and_name  (account_id,name)
#  index_autonomia_prospecting_lists_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Autonomia::Prospecting::List < ApplicationRecord
  self.table_name = 'autonomia_prospecting_lists'

  belongs_to :account
  belongs_to :user, optional: true

  has_many :list_leads, class_name: 'Autonomia::Prospecting::ListLead', foreign_key: :prospect_list_id, dependent: :destroy,
                        inverse_of: :list
  has_many :leads, through: :list_leads, source: :lead

  enum status: { active: 0, archived: 1 }

  validates :name, presence: true
end
