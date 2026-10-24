# Read-only view over the crm_meta_conversion_events ledger for the CRM UI.
#
# index   -> latest Meta conversion per card for a set of visible cards (Lista "Meta"
#            column + card drawer badge). Batched by card_ids so it is only fetched
#            when Meta sync is actually active.
# summary -> aggregate sync health for the dashboard (counts by status/event_type,
#            accepted revenue, last delivery), optionally scoped to a pipeline/window.
#
# The ledger never stores the Meta token, so nothing here can leak a secret.
class Api::V1::Accounts::Crm::MetaConversionsController < Api::V1::Accounts::Crm::BaseController
  def index
    authorize ::Crm::Card

    visible_ids = policy_scope(::Crm::Card).where(id: permitted_card_ids).pluck(:id)
    return render json: { payload: [] } if visible_ids.empty?

    latest_per_card = Crm::MetaConversionEvent
                      .where(account_id: Current.account.id, card_id: visible_ids)
                      .order(created_at: :desc)
                      .group_by(&:card_id)
                      .transform_values(&:first)

    render json: { payload: latest_per_card.values.map { |event| serialize(event) } }
  end

  # A receita aceita é número da equipe (painel de Números): a mesma régua dos relatórios (Crm::ReportPolicy). Com
  # `crm_numeros_lentes` (#1897, Decisão 2), o agente sem função deixa de ler.
  def summary
    authorize %i[crm report], :view?, policy_class: ::Crm::ReportPolicy

    scope = filtered_scope
    render json: { payload: {
      by_status: countable_statuses(scope),
      by_event_type: scope.group(:event_type).count,
      accepted_count: scope.accepted.count,
      # Grouped by currency: cards are not all BRL, and a mixed-currency sum under a
      # single R$ label would be wrong. Null currency buckets under 'BRL' (card default).
      # Valor de venda (#2075): nil sem `sales_value_view`; as contagens ficam.
      accepted_value_by_currency: (accepted_value_by_currency(scope) if ::Crm::ValorDeVenda.ve?(Current.account_user)),
      last_sent_at: scope.accepted.maximum(:sent_at)
    } }
  end

  private

  def filtered_scope
    scope = visible_events
    scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    scope = scope.where(created_at: params[:since]..) if params[:since].present?
    scope = scope.where(created_at: ..params[:until]) if params[:until].present?
    scope
  end

  # Acesso por funil (#1148, PR D): o resumo do painel soma só os funis da pessoa; pedir outro funil é 404, como nos
  # relatórios.
  def visible_events
    events = Crm::MetaConversionEvent.where(account_id: Current.account.id)
    visible = Crm::Access::VisiblePipelines.new(user: Current.user, account: Current.account, account_user: Current.account_user)
    return events unless visible.restricted?

    visible.apply_to_reports(Current.account.crm_pipelines).find(params[:pipeline_id]) if params[:pipeline_id].present?
    events.where(pipeline_id: visible.report_ids)
  end

  # group(:status) returns the integer enum values; map them back to their names.
  def countable_statuses(scope)
    scope.group(:status).count.transform_keys { |value| Crm::MetaConversionEvent.statuses.key(value) || value }
  end

  def accepted_value_by_currency(scope)
    scope.accepted.where(event_type: 'won').group(:currency).sum(:value_cents)
         .each_with_object({}) { |(currency, cents), map| map[currency.presence || 'BRL'] = (map[currency.presence || 'BRL'] || 0) + cents }
  end

  # Accepts card_ids[]=1&card_ids[]=2 or a single card_id; anything non-numeric or a
  # malformed nested-hash param is dropped instead of raising (no 500 on bad input).
  def permitted_card_ids
    ids = params[:card_ids].presence || params[:card_id].presence
    list = ids.is_a?(Array) ? ids : [ids]
    list.filter_map { |value| Integer(value, exception: false) }.reject(&:zero?).uniq
  end

  def serialize(event)
    {
      card_id: event.card_id,
      status: event.status,
      event_type: event.event_type,
      http_code: event.http_code,
      error_message: event.error_message,
      attribution_mode: event.attribution_mode,
      sent_at: event.sent_at,
      event_id: event.event_id
    }
  end
end
