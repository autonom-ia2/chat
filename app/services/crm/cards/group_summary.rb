# Aggregates the filtered card scope into per-group totals for the list view's
# "Group by" headers (count + Σ value). It reuses Crm::Cards::FilterQuery to
# build the EXACT same scope the list index uses (so the summary always matches
# the rows the user sees), then runs a single grouped SQL aggregate.
#
# Contract (consumed by the list group headers / store getGroupSummary):
#   { group_by: 'stage'|'owner'|'acao', groups: [{ key, label, count, sum_cents, currency }] }
#
# `acao` (Lista nova, #2283) conta os grupos de Crm::Cards::ActionGroups pelo mesmo CASE da lista (sort=acao), com o
# mesmo filtro, escopo e `mine`: as cinco chaves sempre, na ordem, com 0 quando vazio; label nil (o texto é do painel).
#
# `key` is the stage_id / owner_id (or nil for "no owner"); `label` is the
# human-readable stage/agent name resolved in one batched lookup.
# Valor de venda (#2075): sem `sales_value_view`, sum_cents vem nil (a contagem fica).
class Crm::Cards::GroupSummary
  GROUP_COLUMNS = {
    'stage' => :stage_id,
    'owner' => :owner_id
  }.freeze

  DEFAULT_CURRENCY = 'BRL'.freeze

  def initialize(scope:, params:, group_by:, conversation_visibility:, value_visible: true)
    @scope = scope
    @value_visible = value_visible
    @params = params
    @group_by = group_by.to_s
    @conversation_visibility = conversation_visibility
  end

  def perform
    return { group_by: @group_by, groups: build_action_groups } if @group_by == Crm::Cards::ActionGroups::SORT
    return empty_result unless GROUP_COLUMNS.key?(@group_by)

    { group_by: @group_by, groups: build_groups }
  end

  private

  def empty_result
    { group_by: @group_by.presence, groups: [] }
  end

  def column
    GROUP_COLUMNS[@group_by]
  end

  # Reuse the list filter pipeline verbatim so the aggregate is computed over
  # the identical row set (filters/search/result/follow-up all honored). The
  # scope passed in is already the Pundit policy_scope from the controller.
  def filtered_scope
    ::Crm::Cards::FilterQuery.new(scope: @scope, params: @params, conversation_visibility: @conversation_visibility).perform
  end

  # Sem includes/preload (#2293): com eles o pluck liga o eager_load e o JOIN das conversas vinculadas repete o card,
  # que contaria e somaria uma vez por conversa. `reorder(nil)` tira a ordem para o GROUP BY não exigir as colunas dela.
  def aggregate_scope
    filtered_scope.except(:includes, :preload, :eager_load, :references).reorder(nil)
  end

  def build_groups
    rows = aggregate_scope
           .group("crm_cards.#{column}")
           .pluck(
             Arel.sql("crm_cards.#{column}"),
             Arel.sql('COUNT(*)'),
             Arel.sql('COALESCE(SUM(crm_cards.value_cents), 0)'),
             Arel.sql("MODE() WITHIN GROUP (ORDER BY crm_cards.currency)")
           )

    labels = label_map(rows.map(&:first))

    rows.map do |key, count, sum_value_cents, currency|
      {
        key: key,
        label: labels[key],
        count: count.to_i,
        sum_cents: (sum_value_cents.to_i if @value_visible),
        currency: currency.presence || DEFAULT_CURRENCY
      }
    end
  end

  def build_action_groups
    rows = aggregate_scope.group(Arel.sql(Crm::Cards::ActionGroups::GROUP_SQL)).pluck(
      Arel.sql(Crm::Cards::ActionGroups::GROUP_SQL), Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(crm_cards.value_cents), 0)'),
      Arel.sql('MODE() WITHIN GROUP (ORDER BY crm_cards.currency)')
    ).index_by(&:first)

    Crm::Cards::ActionGroups::KEYS.map do |group, key|
      _group, count, sum_value_cents, currency = rows[group]
      { key: key, label: nil, count: count.to_i, sum_cents: (sum_value_cents.to_i if @value_visible),
        currency: currency.presence || DEFAULT_CURRENCY }
    end
  end

  # Batched name lookup for every group key in a single query per type. nil keys
  # (cards with no owner) map to nil label so the UI can render its own
  # "Unassigned" placeholder via i18n.
  def label_map(keys)
    ids = keys.compact
    return {} if ids.empty?

    case @group_by
    when 'stage'
      Current.account.crm_pipeline_stages.where(id: ids).pluck(:id, :name).to_h
    when 'owner'
      User.where(id: ids).pluck(:id, :name).to_h
    else
      {}
    end
  end
end
