# O que a tela mostra da coleta (#1073): o gasto do dia, com moeda e conversas iniciadas, quando foi lido, se há
# leitura em andamento e se a carga de 90 dias ainda está chegando. As conversas que vieram de anúncio e o
# "quanto confiar" são contados do nosso lado (Crm::MetaAds::Links::Stats, F2b): a Meta só conta conversa de
# anúncio que leva direto ao WhatsApp.
#
# O dia é o da conta de anúncios, no fuso dela (`today` diz qual é hoje lá). Se a leitura de hoje já rodou e não
# trouxe linha, hoje ainda não teve gasto: a tela mostra zero de hoje, não o último dia com gasto.
class Crm::MetaAds::Insights::Summary
  def self.payload(connection, refreshing:)
    new(connection).payload(refreshing: refreshing)
  end

  def initialize(connection)
    @connection = connection
    @today = connection.ad_account_today
  end

  def payload(refreshing:)
    {
      synced_at: @connection.insights_synced_at, refreshing: refreshing, today: @today,
      backfilling: @connection.insights_backfilled_at.nil? && Crm::MetaAds::Insights::Backfill.running?(@connection.id)
    }.merge(day).merge(Crm::MetaAds::Links::Stats.new(@connection).payload)
  end

  private

  def rows
    Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id)
  end

  def day
    latest = rows.maximum(:date)
    return totals(latest) if latest.present? && (@today.nil? || latest >= @today)
    return { date: @today, spend: '0', currency: rows.where.not(currency: nil).pick(:currency), conversations: 0 } if read_today?
    return totals(latest) if latest.present?

    { date: nil, spend: nil, currency: nil, conversations: nil }
  end

  # A leitura de hoje rodou depois da meia-noite da conta de anúncios.
  def read_today?
    return false if @today.nil? || @connection.insights_synced_at.nil?

    @connection.insights_synced_at.in_time_zone(@connection.ad_account_timezone).to_date >= @today
  end

  def totals(date)
    day_rows = rows.where(date: date)
    spend, conversations = day_rows.pick(Arel.sql('SUM(spend)'), Arel.sql('SUM(conversations_started)'))
    { date: date, spend: spend.to_d.to_s('F'), currency: day_rows.where.not(currency: nil).pick(:currency), conversations: conversations.to_i }
  end
end
