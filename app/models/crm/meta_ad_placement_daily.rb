# Gasto e resultado de um anúncio num dia, por posicionamento (#1073): plataforma (facebook, instagram,
# messenger, audience_network) e posição (feed, story, instagram_reels…), nos nomes que a Meta usa.
# Lida só na carga diária; gravada por upsert, como Crm::MetaAdInsightDaily.
class Crm::MetaAdPlacementDaily < ApplicationRecord
  self.table_name = 'crm_meta_ad_placements_daily'

  belongs_to :account

  validates :ad_account_id, :ad_id, :date, :publisher_platform, :platform_position, :fetched_at, presence: true
end
