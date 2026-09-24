class Api::V1::Accounts::Autonomia::Prospecting::SearchesController < Api::V1::Accounts::Autonomia::Prospecting::BaseController
  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 50

  def index
    ordered_scope = searches_scope.order(created_at: :desc)
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
    search = searches_scope.find(params[:id])
    render json: { payload: search_payload(search, include_leads: true) }
  end

  def create
    result = ::Autonomia::Prospecting::SearchRunner.new(
      account: Current.account,
      user: Current.user,
      params: search_params
    ).perform

    render json: {
      payload: {
        search: search_payload(result.search),
        leads: result.leads.map { |lead| lead_payload(lead) }
      }
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  rescue ::Autonomia::Prospecting::SearchRunner::UnsupportedProviderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ::Autonomia::Prospecting::SearchRunner::ProviderError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    search = searches_scope.find(params[:id])
    search.update!(metadata: search.metadata.to_h.merge(search_settings_metadata))

    render json: { payload: search_payload(search.reload) }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'crm.pipeline_or_stage_not_found' }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    search = searches_scope.find(params[:id])
    search.destroy!

    render json: { payload: { id: search.id } }
  end

  private

  def search_params
    params.require(:search).permit(
      :query,
      :location,
      :radius,
      :area_type,
      :requested_limit,
      :limit,
      :crm_pipeline_id,
      :crm_stage_id,
      categories: [],
      area_config: {},
      metadata: [
        :location_place_id,
        :location_latitude,
        :location_longitude,
        :location_label,
        :sort_key,
        :score_mode,
        :scoring_profile_id,
        :preset_id,
        :decision_maker_type,
        { advanced_filters: {},
          filters: [:auto_expand_radius] }
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

  def search_payload(search, include_leads: false)
    payload = search.as_json(
      only: [
        :id, :query, :location, :radius, :area_type, :area_config, :provider, :status, :requested_limit,
        :created_at, :updated_at
      ]
    )
    lead_ids = Array(search.metadata.to_h['lead_ids'])
    leads = leads_for_search(search)
    payload['results_count'] =
      if search.metadata.to_h.key?('results_count')
        search.metadata.to_h['results_count']
      elsif lead_ids.present?
        lead_ids.size
      else
        leads.count
      end
    payload['crm_pipeline_id'] = search.metadata.to_h['crm_pipeline_id']
    payload['crm_stage_id'] = search.metadata.to_h['crm_stage_id']
    payload['crm_count'] = leads.count { |lead| lead.crm_card_id.present? }
    payload['contact_count'] = leads.count { |lead| lead.contact_id.present? }
    payload['average_score'] = average_score_for(leads)
    payload['ready_count'] = leads.count do |lead|
      lead.status == 'ready_for_campaign'
    end
    payload['location_place_id'] = search.metadata.to_h['location_place_id']
    payload['location_latitude'] = search.metadata.to_h['location_latitude']
    payload['location_longitude'] = search.metadata.to_h['location_longitude']
    payload['location_label'] = search.metadata.to_h['location_label']
    payload['search_filters'] =
      search.metadata.to_h['search_filters'] || search.metadata.to_h['filters'] || {}
    payload['advanced_filters'] = search.metadata.to_h['advanced_filters'] || {}
    payload['sort_key'] = search.metadata.to_h['sort_key']
    payload['score_mode'] = search.metadata.to_h['score_mode']
    payload['scoring_profile_id'] = search.metadata.to_h['scoring_profile_id']
    payload['preset_id'] = search.metadata.to_h['preset_id']
    payload['decision_maker_type'] =
      search.metadata.to_h['decision_maker_type'].presence || ::Autonomia::Prospecting::DecisionMakerType::DEFAULT
    payload['summary'] = {
      results_count: payload['results_count'],
      contact_count: payload['contact_count'],
      crm_count: payload['crm_count'],
      ready_count: payload['ready_count'],
      average_score: payload['average_score'],
      consumed_api_units: search.consumed_api_units.to_i,
      radius_expanded: ActiveModel::Type::Boolean.new.cast(
        search.metadata.to_h['radius_expanded']
      ),
      cached_from_search_id: search.metadata.to_h['cached_from_search_id']
    }
    payload['leads'] = leads.map { |lead| lead_payload(lead) } if include_leads
    payload
  end

  def leads_for_search(search)
    lead_ids = Array(search.metadata.to_h['lead_ids']).map(&:to_i)
    return search.leads.order(created_at: :desc) if lead_ids.blank?

    leads_scope.where(id: lead_ids).index_by(&:id).values_at(*lead_ids).compact
  end

  def lead_payload(lead)
    lead.as_json(
      only: [
        :id, :provider, :provider_place_id, :name, :phone, :website, :address, :city, :state, :country,
        :latitude, :longitude, :rating, :reviews_count, :category, :status, :discard_reason,
        :score, :priority_score, :priority_position, :search_rank, :score_breakdown, :negative_factors, :human_insight,
        :enrichment_status, :enrichment_requested_at, :enrichment_completed_at, :enrichment_source, :enrichment_error,
        :enriched_data, :decision_name, :decision_role, :decision_confidence, :decision_source_url, :decision_linkedin,
        :decision_instagram, :enriched_email, :enriched_whatsapp, :enriched_instagram, :enriched_linkedin,
        :enriched_facebook, :enriched_cnpj, :enrichment_summary,
        :contact_id, :crm_card_id, :created_at, :updated_at
      ]
    ).merge(
      source_label: lead.provider.to_s.humanize,
      contact_status: lead.contact_id.present? ? 'created' : 'pending',
      crm_status: lead.crm_card_id.present? ? 'created' : 'pending'
    ).merge(
      advanced_filter_payload(lead)
    ).merge(
      reviews_payload(lead)
    ).merge(
      whatsapp_payload(lead)
    )
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

  def average_score_for(leads)
    scored_leads = leads.filter { |lead| lead.score.present? }
    return if scored_leads.blank?

    (scored_leads.sum { |lead| lead.score.to_f } / scored_leads.size).round(1)
  end
end
