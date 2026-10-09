# == Schema Information
#
# Table name: autonomia_prospecting_settings
#
#  id                     :bigint           not null, primary key
#  cache_ttl_seconds      :integer          default(86400), not null
#  daily_limit            :integer
#  default_limit          :integer          default(20), not null
#  enrichment_enabled     :boolean          default(FALSE), not null
#  max_results_per_search :integer          default(20), not null
#  metadata               :jsonb            not null
#  monthly_limit          :integer
#  provider               :string           default("mock"), not null
#  provider_enabled       :boolean          default(FALSE), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#
# Indexes
#
#  index_autonomia_prospecting_settings_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class Autonomia::Prospecting::Setting < ApplicationRecord
  self.table_name = 'autonomia_prospecting_settings'

  belongs_to :account

  validates :provider, presence: true
  validates :default_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :max_results_per_search, numericality: { only_integer: true, greater_than: 0 }
  validates :cache_ttl_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :account_id, uniqueness: true

  def self.for_account(account)
    find_or_create_by!(account: account)
  end
end
