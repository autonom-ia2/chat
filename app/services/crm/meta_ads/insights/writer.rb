# Grava as linhas da Insights API (#1073): uma por anúncio e dia em Crm::MetaAdInsightDaily e, com
# posicionamento, em Crm::MetaAdPlacementDaily. Sempre por upsert no índice único: reler um dia sobrescreve
# (CA-2.4). Os nomes de anúncio, conjunto e campanha que vêm junto renovam o cache de nomes
# (Crm::MetaAdObject), sem tocar na prévia nem na miniatura do anúncio. A frequência de 7 dias (F5) vai para
# Crm::MetaAdFrequencyWindow, uma linha por anúncio e fim de janela.
class Crm::MetaAds::Insights::Writer
  ATTRIBUTION_WINDOW = '7d_click'.freeze
  CONVERSATION_ACTION = 'onsite_conversion.messaging_conversation_started_7d'.freeze
  CURRENCY_LIMIT = 3
  NAME_COLUMNS = %i[name object_type campaign_id adset_id fetched_at].freeze

  def initialize(connection)
    @connection = connection
    @now = Time.current
  end

  def ads!(rows)
    records = rows.filter_map { |row| ad_record(row) }.index_by { |record| [record[:ad_id], record[:date]] }.values
    return 0 if records.empty?

    # Lote vindo da Meta, já normalizado aqui; o índice único é a garantia de "um por anúncio e dia".
    Crm::MetaAdInsightDaily.upsert_all(records, unique_by: :idx_crm_meta_ad_insights_daily_unique) # rubocop:disable Rails/SkipsModelValidations
    write_names!(rows)
    records.size
  end

  def placements!(rows)
    records = rows.filter_map { |row| placement_record(row) }
                  .index_by { |record| record.values_at(:ad_id, :date, :publisher_platform, :platform_position) }.values
    return 0 if records.empty?

    Crm::MetaAdPlacementDaily.upsert_all(records, unique_by: :idx_crm_meta_ad_placements_daily_unique) # rubocop:disable Rails/SkipsModelValidations
    records.size
  end

  # A frequência de `window_days` dias por anúncio (F5, D5.4). `date_end` é o `date_stop` que a Meta devolveu,
  # nunca "ontem" calculado aqui: é ele que diz ao consultor se a janela ainda vale.
  def frequency_windows!(rows, window_days:)
    records = rows.filter_map { |row| window_record(row, window_days) }.index_by { |record| record.values_at(:ad_id, :date_end) }.values
    return 0 if records.empty?

    Crm::MetaAdFrequencyWindow.upsert_all(records, unique_by: :idx_crm_meta_ad_freq_windows_unique) # rubocop:disable Rails/SkipsModelValidations
    records.size
  end

  private

  def window_record(row, window_days)
    return if row['ad_id'].blank?

    {
      account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, ad_id: row['ad_id'].to_s,
      adset_id: row['adset_id'].presence, window_days: window_days, date_end: Date.iso8601(row['date_stop'].to_s),
      impressions: row['impressions'].to_i, reach: row['reach'].to_i, frequency: row['frequency'].presence&.to_d, fetched_at: @now
    }
  rescue ArgumentError
    nil
  end

  def ad_record(row)
    base = base_record(row)
    return if base.nil?

    base.merge(
      adset_id: row['adset_id'].presence, campaign_id: row['campaign_id'].presence,
      currency: row['account_currency'].to_s.first(CURRENCY_LIMIT).presence,
      reach: row['reach'].to_i, frequency: row['frequency'].presence&.to_d,
      actions: Array(row['actions']), attribution_window: ATTRIBUTION_WINDOW
    )
  end

  def placement_record(row)
    base = base_record(row)
    return if base.nil? || row['publisher_platform'].blank? || row['platform_position'].blank?

    base.merge(publisher_platform: row['publisher_platform'], platform_position: row['platform_position'])
  end

  def base_record(row)
    date = Date.iso8601(row['date_start'].to_s)
    return if row['ad_id'].blank?

    {
      account_id: @connection.account_id, ad_account_id: @connection.ad_account_id, ad_id: row['ad_id'].to_s, date: date,
      spend: row['spend'].to_d, impressions: row['impressions'].to_i, link_clicks: row['inline_link_clicks'].to_i,
      conversations_started: conversations(row), fetched_at: @now
    }
  rescue ArgumentError
    nil
  end

  # Com a janela fixa, cada ação traz o valor nela ("7d_click"); sem ele, o valor padrão.
  def conversations(row)
    action = Array(row['actions']).find { |entry| entry.is_a?(Hash) && entry['action_type'] == CONVERSATION_ACTION }
    return 0 if action.nil?

    (action[ATTRIBUTION_WINDOW] || action['value']).to_i
  end

  def write_names!(rows)
    records = rows.flat_map { |row| name_records(row) }.index_by { |record| record[:meta_object_id] }.values
    return if records.empty?

    Crm::MetaAdObject.upsert_all(records, unique_by: :idx_crm_meta_ad_objects_account_object, update_only: NAME_COLUMNS) # rubocop:disable Rails/SkipsModelValidations
  end

  def name_records(row)
    [
      name_record(row['ad_id'], row['ad_name'], 'ad', campaign_id: row['campaign_id'], adset_id: row['adset_id']),
      name_record(row['adset_id'], row['adset_name'], 'adset', campaign_id: row['campaign_id'], adset_id: nil),
      name_record(row['campaign_id'], row['campaign_name'], 'campaign', campaign_id: nil, adset_id: nil)
    ].compact
  end

  def name_record(id, name, type, campaign_id:, adset_id:)
    return if id.blank? || name.blank?

    {
      account_id: @connection.account_id, meta_object_id: id.to_s, object_type: type,
      name: name.to_s.first(Crm::MetaAdObject::NAME_LIMIT), campaign_id: campaign_id.presence, adset_id: adset_id.presence,
      fetched_at: @now
    }
  end
end
