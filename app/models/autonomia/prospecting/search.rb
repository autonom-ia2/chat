# == Schema Information
#
# Table name: autonomia_prospecting_searches
#
#  id                 :bigint           not null, primary key
#  area_config        :jsonb            not null
#  area_type          :string           default("radius"), not null
#  cache_expires_at   :datetime
#  cache_fingerprint  :string
#  categories         :jsonb            not null
#  consumed_api_units :integer          default(0), not null
#  location           :string
#  metadata           :jsonb            not null
#  provider           :string           default("mock"), not null
#  query              :string           not null
#  radius             :integer
#  requested_limit    :integer          default(20), not null
#  status             :integer          default("pending"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  user_id            :bigint
#
# Indexes
#
#  idx_autonomia_prospecting_searches_acc_area         (account_id,area_type)
#  idx_autonomia_prospecting_searches_acc_cache_fp     (account_id,cache_fingerprint)
#  idx_autonomia_prospecting_searches_acc_created      (account_id,created_at)
#  index_autonomia_prospecting_searches_on_account_id  (account_id)
#  index_autonomia_prospecting_searches_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Autonomia::Prospecting::Search < ApplicationRecord
  self.table_name = 'autonomia_prospecting_searches'

  belongs_to :account
  belongs_to :user, optional: true
  has_many :leads, class_name: 'Autonomia::Prospecting::Lead', foreign_key: :prospect_search_id, dependent: :nullify, inverse_of: :search

  enum status: { pending: 0, completed: 1, failed: 2, cached: 3 }

  validates :query, presence: true
  validates :provider, presence: true
  validates :area_type, inclusion: { in: %w[radius viewport] }
  validates :requested_limit, numericality: { only_integer: true, greater_than: 0 }
  validates :consumed_api_units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
