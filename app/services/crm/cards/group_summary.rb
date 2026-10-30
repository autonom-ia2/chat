# Aggregates the filtered card scope into per-group totals for the list view's
# "Group by" headers (count + Σ value). It reuses Crm::Cards::FilterQuery to
# build the EXACT same scope the list index uses (so the summary always matches
# the rows the user sees), then runs a single grouped SQL aggregate.
#
# Contract (consumed by the list group headers / store getGroupSummary):
#   { group_by: 'stage'|'owner'|'acao'|'quem_cuida', groups: [{ key, label, count, sum_cents, currency }] }
#
# `acao` (Lista nova, #2283) conta os grupos de Crm::Cards::ActionGroups pelo mesmo CASE da lista (sort=acao), com o
# mesmo filtro, escopo e `mine`: as cinco chaves sempre, na ordem, com 0 quando vazio; label nil (o texto é do painel).
#
# `quem_cuida` (Lista nova, "Organizar por", #2379) conta por quem cuida, a mesma regra da linha (Crm::Cards::OrganizarPor):
# key "agent:ID" ou "bot:ID", type e label com o nome; quem ninguém cuida vem com key, type e label nil.
#
# Uma linha por card: a contagem tira o includes/preload da base (o pluck com includes faria o eager_load das conversas
# vinculadas e repetiria o card com várias conversas).
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
    return { group_by: @group_by, groups: build_quem_cuida_groups } if @group_by == Crm::Cards::OrganizarPor::QUEM_CUIDA
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

  def build_groups
    # `reorder(nil)` drops any default ordering so the GROUP BY aggregate is not
    # forced to also select non-aggregated ordering columns.
    rows = card_rows_scope
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

  # Sem includes/preload: a contagem é só dos cards, uma linha por card (nada de JOIN de associação no meio).
  def card_rows_scope
    filtered_scope.except(:includes, :preload, :eager_load, :references).reorder(nil)
  end

  def aggregate_columns
    [Arel.sql('COUNT(*)'), Arel.sql('COALESCE(SUM(crm_cards.value_cents), 0)'),
     Arel.sql('MODE() WITHIN GROUP (ORDER BY crm_cards.currency)')]
  end

  def build_quem_cuida_groups
    tipo = Arel.sql(Crm::Cards::OrganizarPor::QUEM_TIPO)
    id = Arel.sql(Crm::Cards::OrganizarPor::QUEM_ID)
    rows = card_rows_scope.group(tipo, id).pluck(tipo, id, *aggregate_columns)
    names = quem_cuida_names(rows)

    rows.map do |type, key_id, count, sum_value_cents, currency|
      { key: (type && "#{type}:#{key_id}"), type: type, label: names[[type, key_id]], count: count.to_i,
        sum_cents: (sum_value_cents.to_i if @value_visible), currency: currency.presence || DEFAULT_CURRENCY }
    end
  end

  # Os nomes numa consulta por tipo. Sem filtro de conta: o id vem de um card da conta, e o dono que saiu da conta
  # continua no card (a linha mostra o nome dele, Crm::Card#current_responsible).
  def quem_cuida_names(rows)
    people = User.where(id: ids_of(rows, 'agent')).pluck(:id, :name).to_h.transform_keys { |pid| ['agent', pid] }
    bots = AgentBot.where(id: ids_of(rows, 'bot')).pluck(:id, :name).to_h.transform_keys { |bid| ['bot', bid] }
    people.merge(bots)
  end

  def ids_of(rows, type)
    rows.select { |row| row.first == type }.map(&:second)
  end

  def build_action_groups
    scope = card_rows_scope
    rows = scope.group(Arel.sql(Crm::Cards::ActionGroups::GROUP_SQL)).pluck(
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
