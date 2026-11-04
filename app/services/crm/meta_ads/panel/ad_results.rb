# O que a Meta mede em cada anúncio no período (#2521), somado das linhas diárias (Crm::MetaAdInsightDaily): vezes que
# apareceu, cliques e as ações da Insights API que o painel mostra — comentários, engajamento com a publicação,
# visualizações de vídeo e leads. É a medida do anúncio que não abre conversa (Panel::Report#other_ad_row) e o número de
# comentários de todo anúncio na lista.
#
# Cada ação vale o número da janela fixa da coleta (Insights::Writer::ATTRIBUTION_WINDOW) quando a Meta o manda, senão o
# valor padrão, como a contagem de conversas do Writer. A Meta não manda "visitas ao perfil" em `actions` (referência
# "Ads Action Stats", conferida em 04/11/2026): o anúncio de perfil fica com cliques e engajamento.
class Crm::MetaAds::Panel::AdResults
  ACTIONS = {
    comments: 'comment', post_engagement: 'post_engagement', video_views: 'video_view', leads: 'lead'
  }.freeze
  EMPTY = { impressions: 0, link_clicks: 0 }.merge(ACTIONS.transform_values { 0 }).freeze

  # insights: as linhas de gasto do período.
  def initialize(insights)
    @insights = insights
  end

  def for(ad_id)
    all.fetch(ad_id, EMPTY)
  end

  private

  def all
    @all ||= @insights.pluck(:ad_id, :impressions, :link_clicks, :actions).each_with_object({}) do |(ad_id, impressions, clicks, actions), sums|
      sums[ad_id] = add(sums.fetch(ad_id, EMPTY), impressions, clicks, actions)
    end
  end

  def add(sum, impressions, clicks, actions)
    counts = action_counts(actions)
    sum.merge(impressions: sum[:impressions] + impressions.to_i, link_clicks: sum[:link_clicks] + clicks.to_i)
       .merge(ACTIONS.keys.index_with { |key| sum[key] + counts.fetch(ACTIONS[key], 0) })
  end

  def action_counts(actions)
    Array(actions).select { |entry| entry.is_a?(Hash) && ACTIONS.value?(entry['action_type']) }
                  .to_h { |entry| [entry['action_type'], (entry[Crm::MetaAds::Insights::Writer::ATTRIBUTION_WINDOW] || entry['value']).to_i] }
  end
end
