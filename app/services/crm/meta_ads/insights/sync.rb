# Leitura síncrona da Insights API para uma conexão (#1073).
#
# - `today`: o gasto de hoje, por anúncio. Roda a cada 30 minutos e quando alguém abre a tela (Refresh).
# - `recent`: os 3 dias completos anteriores, por anúncio e por posicionamento. Roda todo dia às 4h, porque a
#   Meta corrige números recentes; o upsert sobrescreve o que já estava gravado (CA-2.4). Depois, a frequência
#   dos últimos 7 dias (F5, D5.4), que o consultor usa na fadiga e na escala.
#
# Devolve :ok, :skipped (conexão que não pode ser lida agora), :paused (limite de uso) ou o símbolo de
# Failure.handle!.
#
# A leitura de frequência é opcional: roda mesmo se a de posicionamento falhou, pula com a conta em pausa e, no
# erro, só registra o uso e o log. Nunca passa por Failure.handle!: um código 100 por parâmetro errado na consulta
# nova não pode desligar a conexão. O resultado do `recent` continua sendo o da leitura de posicionamento.
class Crm::MetaAds::Insights::Sync
  SCOPES = %w[today recent].freeze
  FREQUENCY_WINDOW = 7

  def initialize(connection)
    @connection = connection
  end

  def perform(scope)
    raise ArgumentError, "unknown scope #{scope}" unless SCOPES.include?(scope)
    return :skipped unless @connection.insights_readable?
    return :paused if Crm::MetaAds::Insights::Usage.paused?(@connection.ad_account_id)

    learn_timezone
    outcome = scope == 'today' ? read_today : read_recent
    @connection.update!(insights_synced_at: Time.current) if outcome == :ok && scope == 'today'
    outcome
  end

  private

  # Conexão feita antes da F2a não sabe o fuso da conta de anúncios: uma leitura da conta resolve, uma vez.
  def learn_timezone
    return if @connection.ad_account_timezone.present?

    result = client.ad_account(@connection.ad_account_id)
    timezone = result.ok ? result.data.to_h['timezone_name'].presence : nil
    @connection.update!(ad_account_timezone: timezone) if timezone
  end

  def read_today
    read(Crm::MetaAds::Insights::Query.ads(Crm::MetaAds::Insights::Query::TODAY)) { |rows| writer.ads!(rows) }
  end

  def read_recent
    outcome = read(Crm::MetaAds::Insights::Query.ads(Crm::MetaAds::Insights::Query::RECENT)) { |rows| writer.ads!(rows) }
    return outcome unless outcome == :ok

    placements = read(Crm::MetaAds::Insights::Query.placements(Crm::MetaAds::Insights::Query::RECENT)) { |rows| writer.placements!(rows) }
    read_frequency
    placements
  end

  def read_frequency
    return if Crm::MetaAds::Insights::Usage.paused?(@connection.ad_account_id)

    query = Crm::MetaAds::Insights::Query.ads_window(FREQUENCY_WINDOW)
    result = client.each_insights_page(@connection.ad_account_id, query) do |rows|
      writer.frequency_windows!(rows, window_days: FREQUENCY_WINDOW)
    end
    Crm::MetaAds::Insights::Usage.track!(@connection.ad_account_id, result)
    return if result.ok

    Rails.logger.warn("[MetaAdsInsights] frequency act_#{@connection.ad_account_id} skipped " \
                      "http=#{result.http_code.inspect} code=#{result.error_code.inspect}")
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
