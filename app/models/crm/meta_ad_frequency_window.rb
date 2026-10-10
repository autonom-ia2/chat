# Frequência de um anúncio numa janela de dias (#1110, F5 — D5.4), lida da Meta sem `time_increment`: alcance
# não soma entre dias, então a de 7 dias não sai das linhas diárias de Crm::MetaAdInsightDaily. Gravada por
# upsert (Crm::MetaAds::Insights::Writer#frequency_windows!); `date_end` é o `date_stop` da Meta.
class Crm::MetaAdFrequencyWindow < ApplicationRecord
  self.table_name = 'crm_meta_ad_frequency_windows'

  belongs_to :account

  validates :ad_account_id, :ad_id, :window_days, :date_end, :fetched_at, presence: true
end
