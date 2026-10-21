# Para onde leva cada conjunto com gasto (#2054), que o painel usa para separar os anúncios que trazem conversa
# (Crm::MetaAds::Panel::AdDestinations). A Insights API não manda o destino: uma leitura da lista de conjuntos da
# conta de anúncios traz todos de uma vez.
#
# Só chama a Meta quando algum conjunto com gasto em WINDOW ainda não tem destino: o destino nasce com o conjunto,
# então cada um é lido uma vez. O conjunto que não vem na lista completa (apagado, arquivado) fica UNDEFINED — "não se
# sabe" para o painel — e não é pedido de novo; com a lista cortada no teto de páginas, o que faltou fica para a
# próxima leitura. Leitura opcional, como a de frequência: no erro só registra o uso e o log,
# sem passar por Failure.handle!.
class Crm::MetaAds::Insights::Destinations
  UNKNOWN = Crm::MetaAds::Panel::AdDestinations::UNDEFINED
  LIMIT = 64
  WINDOW = 90.days

  def initialize(connection, client)
    @connection = connection
    @client = client
  end

  def read!
    missing = missing_ids
    return if missing.empty? || Crm::MetaAds::Insights::Usage.paused?(@connection.ad_account_id)

    result = @client.ad_set_destinations(@connection.ad_account_id)
    Crm::MetaAds::Insights::Usage.track!(@connection.ad_account_id, result)
    return skipped(result) unless result.ok

    write!(missing, Array(result.data.to_h['data']), complete: !result.data.to_h['truncated'])
  end

  private

  def missing_ids
    spent = Crm::MetaAdInsightDaily.where(account_id: @connection.account_id, ad_account_id: @connection.ad_account_id,
                                          date: WINDOW.ago.to_date..)
                                   .where.not(adset_id: nil).distinct.pluck(:adset_id)
    known = Crm::MetaAdObject.where(account_id: @connection.account_id, meta_object_id: spent).where.not(destination_type: nil)
                             .pluck(:meta_object_id)
    spent - known
  end

  def write!(missing, rows, complete:)
    listed = destinations_in(rows)
    now = Time.current
    records = missing.filter_map do |id|
      destination = listed[id] || (UNKNOWN if complete)
      destination && { account_id: @connection.account_id, meta_object_id: id, object_type: 'adset', destination_type: destination,
                       created_at: now, updated_at: now }
    end
    return if records.empty?

    Crm::MetaAdObject.upsert_all(records, unique_by: :idx_crm_meta_ad_objects_account_object, # rubocop:disable Rails/SkipsModelValidations
                                          update_only: %i[destination_type])
  end

  # { id do conjunto => destino } do que a Meta listou.
  def destinations_in(rows)
    rows.select { |row| row.is_a?(Hash) }.to_h { |row| [row['id'].to_s, row['destination_type'].to_s.first(LIMIT).presence] }
  end

  def skipped(result)
    Rails.logger.warn("[MetaAdsInsights] destinations act_#{@connection.ad_account_id} skipped " \
                      "http=#{result.http_code.inspect} code=#{result.error_code.inspect}")
  end
end
