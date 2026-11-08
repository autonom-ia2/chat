# CTWA campaign options for the Conversations and Kanban campaign filter pickers.
# Deliberately OUTSIDE the CRM gate (no Crm::BaseController / ensure_crm_enabled):
# the Conversations filter must work even when the CRM module is disabled.
# Agent-level access via the standard conversation policy (index is open to any
# account member); the payload is aggregated ad metadata only, no message content.
class Api::V1::Accounts::CtwaCampaignsController < Api::V1::Accounts::BaseController
  DEFAULT_RANGE_DAYS = 30
  MAX_RANGE_DAYS = 366

  # Aggregates every campaign touch (additional_attributes['campaign_touches'])
  # of the account's conversations per ad: the most recent non-blank headline wins,
  # count is distinct conversations, last_touch_at is the latest touch. Dataset is
  # small (touches are capped per conversation), so plain LATERAL SQL keeps it simple.
  AGGREGATION_SQL = <<~SQL.squish.freeze
    SELECT
      elem ->> 'source_id' AS source_id,
      (ARRAY_AGG(elem ->> 'headline' ORDER BY elem ->> 'touched_at' DESC NULLS LAST)
        FILTER (WHERE COALESCE(elem ->> 'headline', '') <> ''))[1] AS headline,
      (ARRAY_AGG(elem ->> 'source' ORDER BY elem ->> 'touched_at' DESC NULLS LAST))[1] AS source,
      COUNT(DISTINCT conversations.id) AS conversations_count,
      MAX(elem ->> 'touched_at') AS last_touch_at
    FROM conversations
    CROSS JOIN LATERAL jsonb_array_elements(conversations.additional_attributes -> 'campaign_touches') AS elem
    WHERE conversations.account_id = ?
      AND conversations.id IN (%<visible_ids>s)
      AND jsonb_typeof(conversations.additional_attributes -> 'campaign_touches') = 'array'
      AND COALESCE(elem ->> 'source_id', '') <> ''
    GROUP BY elem ->> 'source_id'
    ORDER BY conversations_count DESC, source_id ASC
  SQL

  def index
    authorize ::Conversation, :index?
    authorize %i[crm report], :view? if include_origin_metrics?

    response = { payload: campaign_options }
    response[:origin_metrics] = origin_metrics if include_origin_metrics?
    render json: response
  end

  private

  # Aggregation is scoped to the conversations the requesting agent can actually see
  # (same PermissionFilterService the ConversationFinder uses) — otherwise campaign
  # metadata from inboxes outside the agent's visibility would leak into the picker.
  def visible_conversations
    Conversations::PermissionFilterService.new(
      Current.account.conversations,
      Current.user,
      Current.account
    ).perform
  end

  def campaign_options
    aggregation = format(AGGREGATION_SQL, visible_ids: visible_conversations.reorder(nil).select(:id).to_sql)
    sql = ActiveRecord::Base.sanitize_sql_array([aggregation, Current.account.id])

    rows = without_hidden_ads(ActiveRecord::Base.connection.select_all(sql).to_a)
    rows.map do |row|
      {
        source_id: row['source_id'],
        source: row['source'],
        headline: row['headline'],
        count: row['conversations_count'].to_i,
        last_touch_at: row['last_touch_at']
      }
    end
  end

  # Anúncio de origem (#2271): a função personalizada sem meta_ads_view não recebe as linhas de anúncio (nome e id),
  # aqui e no filtro de Conversas, que usa as mesmas opções. Divulgação, link e publicação continuam; o robô vê tudo e,
  # sem identidade, não vê. O id que foi anúncio em qualquer toque da conta conta como anúncio, como no filtro
  # (Crm::AnuncioDeOrigem::Ids: uma consulta só, com todas as campanhas da lista).
  def without_hidden_ads(rows)
    return rows if Crm::AnuncioDeOrigem.ve_no_contexto?(Current.user, Current.account_user)

    ads = Crm::AnuncioDeOrigem::Ids.de_anuncio(Current.account, rows.pluck('source_id')).to_set
    rows.reject { |row| ads.include?(row['source_id']) }
  end

  def include_origin_metrics?
    ActiveModel::Type::Boolean.new.cast(params[:include_origin_metrics])
  end

  def origin_metrics
    card_filters, binds = origin_metric_card_filters
    Crm::Reports::OriginMetrics.new(
      visible_ids_sql: visible_conversations.reorder(nil).select(:id).to_sql,
      card_filters: card_filters.join(' AND '),
      binds: binds,
      # Valor de venda (#2075): o R$ segue o Crm::ValorDeVenda; a contagem fica.
      value_visible: Crm::ValorDeVenda.ve?(Current.account_user)
    ).perform
  end

  # Only a funnel that counts as sale has revenue (#1151): a card won before its funnel
  # became a service funnel is not a sale.
  def origin_metric_card_filters
    filters = [
      'crm_cards.account_id = ?',
      "(crm_cards.status = ? OR #{Crm::Card.desfecho_sql})",
      'crm_cards.closed_at BETWEEN ? AND ?',
      'crm_cards.pipeline_id IN (SELECT id FROM crm_pipelines WHERE crm_pipelines.account_id = ? AND crm_pipelines.counts_as_sale)'
    ]
    binds = [Current.account.id, Crm::Card.statuses[:won], 'won', since_time, until_time, Current.account.id]

    if params[:pipeline_id].present?
      filters << 'crm_cards.pipeline_id = ?'
      binds << params[:pipeline_id]
    end
    [(filters + origin_metric_scope_filters).compact, binds]
  end

  # Acesso por funil (#1148, PR D, decisão do Rodrigo em 11/10): a soma conta só os cards que a pessoa vê no CRM.
  # Este contato é (#2084): e, por cima, sem a venda de contato fora do funil (parceiro, não é negócio).
  def origin_metric_scope_filters
    [
      Crm::Access::CardScope.new(user: Current.user, account: Current.account, account_user: Current.account_user).ids_condition,
      Crm::Relacao.condicao_sql(Current.account)
    ]
  end

  # #1876: o período é o do fuso da conta, igual aos relatórios do CRM (Crm::Reports::BaseReport).
  def since_time
    @since_time ||= parse_time(params[:since]) || (account_zone.now - DEFAULT_RANGE_DAYS.days).beginning_of_day
  end

  def until_time
    @until_time ||= begin
      parsed = parse_time(params[:until]) || account_zone.now
      max_until = since_time + MAX_RANGE_DAYS.days
      [parsed, max_until].min
    end
  end

  def parse_time(value)
    return if value.blank?

    account_zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def account_zone
    @account_zone ||= Crm::Timezone::Resolver.new(account: Current.account).zone_or_default
  end
end
