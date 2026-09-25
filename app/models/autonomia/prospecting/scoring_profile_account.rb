# == Schema Information
#
# Table name: autonomia_prospecting_scoring_profile_accounts
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  scoring_profile_id :bigint           not null
#
# Indexes
#
#  idx_autonomia_prospecting_scoring_profile_accounts_account  (account_id)
#  idx_autonomia_prospecting_scoring_profile_accounts_unique   (scoring_profile_id,account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (scoring_profile_id => autonomia_prospecting_scoring_profiles.id) ON DELETE => cascade
#
# Conta que pode ver e usar um perfil de nota restrito (#681). Perfil sem nenhuma linha aqui é global.
class Autonomia::Prospecting::ScoringProfileAccount < ApplicationRecord
  self.table_name = 'autonomia_prospecting_scoring_profile_accounts'

  belongs_to :scoring_profile, class_name: 'Autonomia::Prospecting::ScoringProfile'
  belongs_to :account

  validates :account_id, uniqueness: { scope: :scoring_profile_id }
end
