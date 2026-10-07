# Parâmetros das leituras da Insights API (#1073). Uma chamada por conta de anúncios, nível anúncio, um dia
# por linha (CA-2.1) e a janela de atribuição fixa em 7 dias por clique (CA-2.3): as janelas por visualização
# de 7 e 28 dias saíram da API em 12/01/2026 e voltariam vazias, sem erro.
module Crm::MetaAds::Insights::Query
  ATTRIBUTION_WINDOWS = [Crm::MetaAds::Insights::Writer::ATTRIBUTION_WINDOW].freeze
  AD_FIELDS = %w[
    ad_id ad_name adset_id adset_name campaign_id campaign_name account_currency
    spend impressions reach frequency inline_link_clicks actions
  ].join(',').freeze
  PLACEMENT_FIELDS = %w[ad_id spend impressions inline_link_clicks actions].join(',').freeze
  PLACEMENT_BREAKDOWNS = 'publisher_platform,platform_position'.freeze
  WINDOW_FIELDS = %w[ad_id adset_id impressions reach frequency].join(',').freeze

  # Nomes da Meta para os períodos: hoje, os 3 dias completos anteriores e os 90 dias da primeira carga.
  TODAY = 'today'.freeze
  RECENT = 'last_3d'.freeze
  BACKFILL = 'last_90d'.freeze

  module_function

  def ads(date_preset)
    base(date_preset).merge(fields: AD_FIELDS)
  end

  def placements(date_preset)
    base(date_preset).merge(fields: PLACEMENT_FIELDS, breakdowns: PLACEMENT_BREAKDOWNS)
  end

  # A frequência dos últimos `days` dias inteiros (F5, D5.4): uma linha por anúncio para o período todo. Sem
  # `time_increment`, porque alcance não soma entre dias, e sem janela de atribuição, porque não lê ações.
  def ads_window(days)
    { level: 'ad', date_preset: "last_#{days}d", fields: WINDOW_FIELDS }
  end

  def base(date_preset)
    { level: 'ad', time_increment: 1, date_preset: date_preset, action_attribution_windows: ATTRIBUTION_WINDOWS.to_json }
  end
end
