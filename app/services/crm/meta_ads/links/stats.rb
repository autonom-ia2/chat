# Números das ligações conversa → anúncio para a tela (#1073, F2b), contados do nosso lado:
#
# - `today`: conversas que vieram de anúncio da Meta hoje, no fuso da conta de anúncios (sem fuso, o do
#   servidor). Vale para anúncio que leva ao WhatsApp e para o que leva ao site, que a Meta não conta como
#   conversa.
# - `confidence`: nos últimos CONFIDENCE_WINDOW, as conversas que vieram de anúncio, pelo melhor que sabemos de
#   cada uma (Crm::MetaAdLink::CERTAINTIES). É o "quanto confiar" no custo por conversa e por venda.
#
# `since:` (F5, D5.8) troca a janela pelo período do painel: o painel em 7 dias confia só nos 7 dias, e
# `window_days` vira o número de dias, no fuso da conta, de `since` até hoje. Sem ele fica a janela de 30 dias
# da aba Conexão.
class Crm::MetaAds::Links::Stats
  CONFIDENCE_WINDOW = 30.days
  RANK = Crm::MetaAdLink::CERTAINTIES.each_with_index.to_h.freeze
  RANK_SQL = Arel.sql("MIN(CASE certainty #{RANK.map { |name, rank| "WHEN '#{name}' THEN #{rank}" }.join(' ')} END)")

  def initialize(connection, since: nil)
    @connection = connection
    @since = since
  end

  def payload
    { ad_conversations_today: today_count, confidence: confidence }
  end

  private

  def links
    Crm::MetaAdLink.where(account_id: @connection.account_id)
  end

  def zone
    (@connection.ad_account_timezone.present? && ActiveSupport::TimeZone[@connection.ad_account_timezone]) || Time.zone
  end

  def today_count
    links.where(touched_at: Time.current.in_time_zone(zone).all_day).distinct.count(:conversation_id)
  end

  def confidence
    best = links.where(touched_at: (@since || CONFIDENCE_WINDOW.ago)..).group(:conversation_id).pluck(RANK_SQL)
    counts = RANK.keys.index_with(0).merge(best.tally.transform_keys { |rank| RANK.key(rank) })
    { window_days: window_days, conversations: best.size }.merge(counts.symbolize_keys)
  end

  def window_days
    return CONFIDENCE_WINDOW.in_days.to_i if @since.nil?

    (Time.current.in_time_zone(zone).to_date - @since.in_time_zone(zone).to_date).to_i + 1
  end
end
