# Gasto e resultado de um anúncio num dia, como a Insights API da Meta entrega (#1073).
#
# Uma linha por conta · conta de anúncios · anúncio · dia. A gravação é sempre por upsert
# (Crm::MetaAds::Insights::Writer): reler um dia sobrescreve. `actions` guarda a lista crua de ações da Meta;
# `conversations_started` é a contagem de conversas por mensagem já extraída dela. A janela de atribuição
# usada vai em cada linha.
class Crm::MetaAdInsightDaily < ApplicationRecord
  self.table_name = 'crm_meta_ad_insights_daily'

  belongs_to :account

  validates :ad_account_id, :ad_id, :date, :attribution_window, :fetched_at, presence: true
end
