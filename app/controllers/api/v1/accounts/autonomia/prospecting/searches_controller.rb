class Api::V1::Accounts::Autonomia::Prospecting::SearchesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  include ::Autonomia::Prospecting::LeadExport

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  rescue_from ::Autonomia::Prospecting::SearchRunner::ScoreEngineError, with: :render_score_unavailable

  # Baixar a planilha de leads é exportar: pede prospecting_manage, não só ver (#2147).
  before_action -> { check_permission_granted!('prospecting_manage') }, only: [:export]

  def index
    ordered_scope = visible_searches_scope.includes(:user).order(created_at: :desc)
    total_count = ordered_scope.count
    searches = ordered_scope.offset((page - 1) * per_page).limit(per_page)

    render json: {
      payload: searches.map { |search| search_payload(search) },
      meta: pagination_payload(total_count)
    }
  end

  # Local no país da conta (#677). Erro do Google chega à tela em português, em vez de lista vazia calada.
  def location_suggestions
    query = params[:query].to_s.strip
    return render json: { payload: [] } if query.length < 3

    return render json: { payload: [] } unless setting.google_places_configured?

    render json: { payload: places_location.suggestions(query) }
  rescue ::Autonomia::Prospecting::SearchRunner::ProviderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def location_details
    place_id = params[:place_id].to_s.strip
    return render json: { error: I18n.t('autonomia.prospecting.errors.location_required') }, status: :unprocessable_entity if place_id.blank?

    return render json: { payload: {} } unless setting.google_places_configured?

    render json: { payload: places_location.details(place_id) }
  rescue ::Autonomia::Prospecting::SearchRunner::ProviderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def show
    search = visible_searches_scope.find(params[:id])
    render json: { payload: search_payload(search, include_leads: true) }
  end

  def create
    result = ::Autonomia::Prospecting::SearchRunner.new(
      account: Current.account,
      user: Current.user,
      params: search_params
    ).perform
    # Enriquecer e verificar WhatsApp no servidor, sem depender da aba aberta (#678).
    ::Autonomia::Prospecting::LeadWorkQueue.after_search(account: Current.account, leads: result.leads)
    leads = reloaded_leads(result.leads)

    render json: {
      payload: {
        search: search_payload(result.search),
        leads: leads.map { |lead| lead_payload(lead, result.search) }
      }
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ::Autonomia::Prospecting::SearchRunner::UnsupportedProviderError, ::Autonomia::Prospecting::SearchRunner::ProviderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    search = visible_searches_scope.find(params[:id])
    search.update!(metadata: search.metadata.to_h.merge(search_settings_metadata))

    render json: { payload: search_payload(search.reload) }
  rescue ActiveRecord::RecordNotFound
    render_crm_send_error('pipeline_not_found', status: :not_found)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # CSV ou Excel dos leads da busca (#682), na ordem de prioridade dela, como o export do Orth.
  def export
    search = visible_searches_scope.find(params[:id])
    scoring = search.metadata.to_h['lead_scoring'].to_h
    send_leads_export(by_priority_position(leads_for_search(search), scoring), scoring: scoring, filename: "busca-#{search.id}")
  end

  # Cada pessoa apaga só as buscas que ela fez, inclusive quem vê as de todos (decisão do Rodrigo, #2693).
  def destroy
    search = visible_searches_scope.where(user_id: Current.user.id).find(params[:id])
    search.destroy!

    render json: { payload: { id: search.id } }
  end

  private

  # Conta virada para a nota do Orth (#681) com a nota fora do ar: o detalhe vai para o log, a tela recebe a frase. Aqui,
  # fora da ação, Current já foi limpo: a conta vem da rota.
  def render_score_unavailable(error)
    Rails.logger.warn("[Prospecting::Searches] score_engine_failed account_id=#{params[:account_id]} error=#{error.message}")
    render json: { error: I18n.t('autonomia.prospecting.errors.score_unavailable') }, status: :unprocessable_entity
  end

  def search_params
    params.require(:search).permit(
      :query, :location, :radius, :area_type, :requested_limit, :limit, :crm_pipeline_id, :crm_stage_id, :fresh,
      categories: [],
      area_config: {},
      metadata: [
        :location_place_id, :location_latitude, :location_longitude, :location_label, :sort_key, :score_mode,
        :scoring_profile_id, :preset_id, :decision_maker_type,
        { advanced_filters: {}, filters: [:auto_expand_radius] }
      ]
    )
  end

  def search_update_params
    params.require(:search).permit(:crm_pipeline_id, :crm_stage_id)
  end

  def places_location
    ::Autonomia::Prospecting::Providers::GooglePlacesLocation.new(
      api_key: setting.google_places_api_key, country: setting.search_country, account_id: Current.account.id
    )
  end

  def search_settings_metadata
    attributes = search_update_params.to_h.symbolize_keys
    pipeline_id = attributes[:crm_pipeline_id].presence
    stage_id = attributes[:crm_stage_id].presence
    pipeline = nil
    stage = nil

    if pipeline_id.present? && stage_id.present?
      pipeline = Current.account.crm_pipelines.active.find(pipeline_id)
      stage = Current.account.crm_pipeline_stages.where(pipeline: pipeline).find(stage_id)
    end

    {
      'crm_pipeline_id' => pipeline&.id,
      'crm_stage_id' => stage&.id
    }
  end

  # O corpo da busca mora em SearchPayload (#2693); os leads vão junto só ao abrir a busca.
  def search_payload(search, include_leads: false)
    leads = leads_for_search(search)
    payload = ::Autonomia::Prospecting::SearchPayload.new(search: search, leads: leads).build
    return payload unless include_leads

    payload.merge('leads' => leads.map { |lead| lead_payload(lead, search) })
  end

  # A fila marca 'queued' por update_all: sem reler, a tela recebia 'pending', verificava pela aba os mesmos números
  # que o job verifica e mostrava Enriquecer livre num lead já na fila. O contato vai junto (nome do contato no lead).
  def reloaded_leads(leads)
    leads.each(&:reload).tap do |reloaded|
      ActiveRecord::Associations::Preloader.new(records: reloaded, associations: lead_preloads).call
    end
  end

  def leads_for_search(search)
    lead_ids = Array(search.metadata.to_h['lead_ids']).map(&:to_i)
    return search.leads.includes(*lead_preloads).order(created_at: :desc) if lead_ids.blank?

    leads_scope.includes(*lead_preloads).where(id: lead_ids).index_by(&:id).values_at(*lead_ids).compact
  end

  # O bloco técnico da nota (componentes, pesos, fatores negativos) só vai para o administrador (#732, item 9).
  # Posição e nota da busca por cima das do lead (#677, #678): as chaves já existem no payload e ficam no mesmo lugar.
  def lead_payload(lead, search)
    visible_lead_payload(lead_payload_builder.build(lead).merge(::Autonomia::Prospecting::SearchPayload.lead_in_search(lead, search)))
  end

  # Posição de prioridade da busca, senão a do lead; sem posição, no fim, na ordem da busca.
  def by_priority_position(leads, scoring)
    leads.each_with_index.sort_by do |lead, index|
      position = scoring.dig(lead.id.to_s, 'priority_position') || lead.priority_position
      [position.nil? ? 1 : 0, position.to_i, index]
    end.map(&:first)
  end

  def page
    @page ||= [params[:page].presence.to_i, 1].max
  end

  def per_page
    @per_page ||= begin
      requested_per_page = params[:per_page].presence.to_i
      requested_per_page = DEFAULT_PER_PAGE if requested_per_page <= 0
      [requested_per_page, MAX_PER_PAGE].min
    end
  end

  def pagination_payload(total_count)
    total_pages = (total_count.to_f / per_page).ceil

    {
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_more: page < total_pages
    }
  end
end
