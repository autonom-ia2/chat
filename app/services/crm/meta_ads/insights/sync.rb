# Leitura síncrona da Insights API para uma conexão (#1073).
#
# - `today`: o gasto de hoje, por anúncio. Roda a cada 30 minutos e quando alguém abre a tela (Refresh).
# - `recent`: os 3 dias completos anteriores, por anúncio e por posicionamento. Roda todo dia às 4h, porque a
#   Meta corrige números recentes; o upsert sobrescreve o que já estava gravado (CA-2.4).
#
# Devolve :ok, :skipped (conexão que não pode ser lida agora), :paused (limite de uso) ou o símbolo de
# Failure.handle!.
class Crm::MetaAds::Insights::Sync
  SCOPES = %w[today recent].freeze

  def initialize(connection)
    @connection = connection
  end

  def perform(scope)
    raise ArgumentError, "unknown scope #{scope}" unless SCOPES.include?(scope)
    return :skipped unless @connection.insights_readable?
    return :paused if Crm::MetaAds::Insights::Usage.paused?(@connection.ad_account_id)

    outcome = scope == 'today' ? read_today : read_recent
    @connection.update!(insights_synced_at: Time.current) if outcome == :ok && scope == 'today'
    outcome
  end

  private

  def read_today
    read(Crm::MetaAds::Insights::Query.ads(Crm::MetaAds::Insights::Query::TODAY)) { |rows| writer.ads!(rows) }
  end

  def read_recent
    outcome = read(Crm::MetaAds::Insights::Query.ads(Crm::MetaAds::Insights::Query::RECENT)) { |rows| writer.ads!(rows) }
    return outcome unless outcome == :ok

    read(Crm::MetaAds::Insights::Query.placements(Crm::MetaAds::Insights::Query::RECENT)) { |rows| writer.placements!(rows) }
  end

  def read(query, &)
    result = client.each_insights_page(@connection.ad_account_id, query, &)
    return Crm::MetaAds::Insights::Failure.handle!(@connection, result) unless result.ok

    Crm::MetaAds::Insights::Usage.track!(@connection.ad_account_id, result)
    :ok
  end

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def writer
    @writer ||= Crm::MetaAds::Insights::Writer.new(@connection)
  end
end
