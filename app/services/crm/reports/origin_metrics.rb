# Vendas ganhas por origem para o bloco "De onde vieram" de Números (GET ctwa_campaigns?include_origin_metrics=true).
#
# #1876: cada venda ganha sai com o toque de origem (o primeiro) ou sem nenhum. A origem é resolvida em Ruby
# (#origin_source), pela mesma regra que grava o toque (Ctwa::CampaignBuilder), para não haver "vazio = anúncio". Venda
# sem toque em nenhuma conversa do card vai para "Sem origem" (`none`); a que tem toque numa conversa que a pessoa não
# vê continua fora da soma.
class Crm::Reports::OriginMetrics
  NO_ORIGIN = 'none'.freeze

  ORIGIN_METRICS_SQL = <<~SQL.squish.freeze
    WITH visible_conversation_ids AS (%<visible_ids>s),
    eligible_cards AS (
      SELECT
        crm_cards.id AS card_id,
        crm_cards.account_id AS account_id,
        crm_cards.conversation_id AS conversation_id,
        crm_cards.currency AS currency,
        crm_cards.value_cents AS value_cents
      FROM crm_cards
      WHERE %<card_filters>s
    ),
    candidate_origins AS (
      SELECT
        eligible_cards.card_id,
        eligible_cards.currency,
        eligible_cards.value_cents,
        conversations.id AS conversation_id,
        conversations.additional_attributes -> 'campaign' AS campaign,
        NULLIF(conversations.additional_attributes -> 'campaign' ->> 'touched_at', '') AS touched_at
      FROM eligible_cards
      INNER JOIN conversations ON conversations.id = eligible_cards.conversation_id
        AND conversations.account_id = eligible_cards.account_id
      INNER JOIN visible_conversation_ids ON visible_conversation_ids.id = conversations.id
      WHERE jsonb_exists(conversations.additional_attributes, 'campaign')
      UNION ALL
      SELECT
        eligible_cards.card_id,
        eligible_cards.currency,
        eligible_cards.value_cents,
        conversations.id AS conversation_id,
        conversations.additional_attributes -> 'campaign' AS campaign,
        NULLIF(conversations.additional_attributes -> 'campaign' ->> 'touched_at', '') AS touched_at
      FROM eligible_cards
      INNER JOIN crm_card_conversations ON crm_card_conversations.card_id = eligible_cards.card_id
        AND crm_card_conversations.account_id = eligible_cards.account_id
      INNER JOIN conversations ON conversations.id = crm_card_conversations.conversation_id
        AND conversations.account_id = eligible_cards.account_id
      INNER JOIN visible_conversation_ids ON visible_conversation_ids.id = conversations.id
      WHERE jsonb_exists(conversations.additional_attributes, 'campaign')
    ),
    canonical_cards AS (
      SELECT DISTINCT ON (card_id)
        candidate_origins.campaign,
        candidate_origins.currency,
        candidate_origins.value_cents
      FROM candidate_origins
      ORDER BY card_id, touched_at ASC NULLS FIRST, conversation_id ASC
    ),
    cards_without_origin AS (
      SELECT NULL::jsonb AS campaign, eligible_cards.currency, eligible_cards.value_cents
      FROM eligible_cards
      WHERE NOT EXISTS (
        SELECT 1
        FROM conversations
        WHERE conversations.account_id = eligible_cards.account_id
          AND jsonb_exists(conversations.additional_attributes, 'campaign')
          AND (
            conversations.id = eligible_cards.conversation_id
            OR conversations.id IN (
              SELECT crm_card_conversations.conversation_id
              FROM crm_card_conversations
              WHERE crm_card_conversations.card_id = eligible_cards.card_id
                AND crm_card_conversations.account_id = eligible_cards.account_id
            )
          )
      )
    )
    SELECT campaign, currency, value_cents FROM canonical_cards
    UNION ALL
    SELECT campaign, currency, value_cents FROM cards_without_origin
  SQL

  # visible_ids_sql: as conversas que a pessoa vê; card_filters/binds: as vendas que entram (conta, período, funil).
  def initialize(visible_ids_sql:, card_filters:, binds:)
    @visible_ids_sql = visible_ids_sql
    @card_filters = card_filters
    @binds = binds
  end

  def perform
    query = format(ORIGIN_METRICS_SQL, visible_ids: @visible_ids_sql, card_filters: @card_filters)
    sql = ActiveRecord::Base.sanitize_sql_array([query, *@binds])
    rows = ActiveRecord::Base.connection.select_all(sql).group_by { |row| origin_source(row['campaign']) }
    rows.map { |source, sales| origin_row(source, sales) }.sort_by { |row| origin_order(row) }
  end

  private

  # #1876: o toque sem `source` (gravado antes do campo existir) tem a origem resolvida pela regra do próprio toque, a
  # mesma de Ctwa::CampaignBuilder; nunca vira anúncio por padrão.
  def origin_source(raw_campaign)
    campaign = raw_campaign.is_a?(String) ? JSON.parse(raw_campaign) : raw_campaign
    return NO_ORIGIN unless campaign.is_a?(Hash) && campaign.present?

    campaign['source'].presence || Ctwa::CampaignBuilder.source_for(campaign.symbolize_keys)
  end

  def origin_row(source, sales)
    totals = sales.group_by { |sale| sale['currency'] }.sort.map do |currency, list|
      { currency: currency, value_cents: list.sum { |sale| sale['value_cents'].to_i } }
    end
    { source: source, won_count: sales.size, won_value_by_currency: totals }
  end

  # Mais vendas primeiro; "Sem origem" sempre por último.
  def origin_order(row)
    [row[:source] == NO_ORIGIN ? 1 : 0, -row[:won_count], row[:source]]
  end
end
