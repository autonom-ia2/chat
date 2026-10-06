# O que a tela mostra da coleta (#1073): o último dia lido da conta de anúncios ligada, com gasto, moeda e
# conversas iniciadas, quando foi lido e se há leitura em andamento. O dia é o da conta de anúncios, no fuso
# dela; a tela decide se é "hoje".
class Crm::MetaAds::Insights::Summary
  def self.payload(connection, refreshing:)
    new(connection).payload(refreshing: refreshing)
  end

  def initialize(connection)
    @connection = connection
  end

  def payload(refreshing:)
    { synced_at: @connection.insights_synced_at, refreshing: refreshing }.merge(latest_day)
  end

  private

  def latest_day
    rows = Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id)
    date = rows.maximum(:date)
    return { date: nil, spend: nil, currency: nil, conversations: nil } if date.nil?

    day = rows.where(date: date)
    spend, conversations = day.pick(Arel.sql('SUM(spend)'), Arel.sql('SUM(conversations_started)'))
    { date: date, spend: spend.to_d.to_s('F'), currency: day.where.not(currency: nil).pick(:currency), conversations: conversations.to_i }
  end
end
