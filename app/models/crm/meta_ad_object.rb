# == Schema Information
#
# Table name: crm_meta_ad_objects
#
#  id             :bigint           not null, primary key
#  fetched_at     :datetime
#  meta_object_id :string           not null
#  name           :string(255)
#  object_type    :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  adset_id       :string
#  campaign_id    :string
#
# Indexes
#
#  idx_crm_meta_ad_objects_account_object  (account_id,meta_object_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
# Cache dos nomes que a Graph API devolve para os IDs de anúncio, conjunto e campanha (#1034).
# Válido por CACHE_TTL; depois disso o nome é buscado de novo (a campanha pode ter sido renomeada).
# A coluna se chama `meta_object_id`, não `object_id`: este nome é de Object#object_id e o
# ActiveRecord não geraria o leitor do atributo.
class Crm::MetaAdObject < ApplicationRecord
  self.table_name = 'crm_meta_ad_objects'

  TYPES = %w[ad adset campaign].freeze
  CACHE_TTL = 7.days
  NAME_LIMIT = 255

  belongs_to :account

  validates :meta_object_id, presence: true, uniqueness: { scope: :account_id }
  validates :object_type, inclusion: { in: TYPES }, allow_nil: true

  scope :fresh, -> { where(fetched_at: CACHE_TTL.ago..) }
end
