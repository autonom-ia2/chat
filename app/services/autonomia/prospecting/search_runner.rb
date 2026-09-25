require 'digest'
require 'json'

class Autonomia::Prospecting::SearchRunner
  AREA_TYPES = Autonomia::Prospecting::SearchArea::TYPES
  LOCATION_COORDINATE_KEYS = %w[location_latitude location_longitude].freeze
  # Teto de produto do pedido (#683): 3 páginas de 20 no Google (#678).
  MAX_REQUESTED_LIMIT = Autonomia::Prospecting::Providers::GooglePlacesProvider::MAX_RESULTS
  # Lead que já existe ganha só as chaves de metadata que a busca traz (ENRIQ-57), e a verificação de WhatsApp sai
  # quando é de outro número (ENRIQ-69). A decisão é do banco, sobre o metadata da hora da gravação: uma verificação
  # que termina depois de a busca ler o lead também é julgada. Parâmetros: número a supor quando a verificação não
  # guarda o dela, E.164 novo do lead, chaves novas.
  METADATA_MERGE_SQL = <<~SQL.squish.freeze
    metadata = (
      CASE
        WHEN COALESCE(metadata -> 'whatsapp_verification' ->> 'status', 'queued') <> 'queued'
         AND COALESCE(metadata -> 'whatsapp_verification' ->> 'phone', ?::text) IS DISTINCT FROM ?::text
        THEN metadata - 'whatsapp_verification'
        ELSE metadata
      END
    ) || ?::jsonb
  SQL

  Result = Struct.new(:search, :leads, keyword_init: true)

  class UnsupportedProviderError < StandardError; end
  class ProviderError < StandardError; end
  ScoreEngineError = Autonomia::Prospecting::Scoring::SearchScoring::EngineError

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.to_h.symbolize_keys
    @setting = Autonomia::Prospecting::Setting.for_account(account)
  end

  def perform
    validate!
    # Repetir do histórico chama o Google de novo, como no Orth, que não tem cache de busca (#678).
    cached = fresh? ? nil : cached_result
    return cached if cached

    search = create_search!
    # Todas as chamadas ao Google acontecem antes da transação (#678): com a paginação são até 3 páginas por raio, e
    # segurar a conexão do banco enquanto o Google responde trava outras telas.
    provider_result = search_provider_results
    leads = persist_results!(search, provider_result)

    Result.new(search: search.reload, leads: leads)
  rescue StandardError => e
    # As chamadas já feitas ao Google foram pagas e entram no uso mostrado nas Configurações mesmo com a busca falha.
    if search&.persisted?
      search.update!(status: :failed, consumed_api_units: @consumed_api_units.to_i,
                     metadata: search.metadata.to_h.merge('error' => e.message))
    end
    raise
  end

  private

  def persist_results!(search, provider_result)
    ActiveRecord::Base.transaction do
      leads = upsert_leads!(search, accepted_with_rank(provider_result[:attributes]))
      score_leads!(leads)
      search.radius = provider_result[:radius]
      search.area_config = area_config_for_radius(provider_result[:radius])
      search.metadata = search.metadata.to_h.merge(results_metadata(leads, provider_result))
      search.status = :completed
      search.consumed_api_units = provider_result[:api_units]
      search.cache_fingerprint = cache_fingerprint
      # Busca parcial não vira cache: a próxima igual tenta o Google de novo em vez de repetir o resultado incompleto.
      search.cache_expires_at = provider_result[:partial] ? nil : cache_expires_at
      search.save!
      leads
    end
  end

  # Filtra antes de cortar no pedido (#678). A posição é a do Google entre as páginas, dada antes de filtrar.
  def accepted_with_rank(attributes_list)
    attributes_list.each_with_index.filter_map do |attributes, index|
      google_rank = index + 1
      next unless advanced_filter_matches?(attributes, google_rank)

      [attributes, google_rank]
    end.first(requested_limit)
  end

  def results_metadata(leads, provider_result)
    {
      'lead_ids' => leads.map(&:id),
      'lead_ranks' => lead_ranks(leads),
      'lead_scoring' => lead_scoring(leads),
      'results_count' => leads.size,
      'search_filters' => search_filters,
      'requested_radius' => radius,
      'radius_expanded' => provider_result[:radius].to_i > radius,
      'partial_results' => provider_result[:partial] == true
    }.merge(@score_engine.shadow_error ? { 'score_shadow_error' => @score_engine.shadow_error } : {})
  end

  # Nota do Orth ao lado da legada em toda busca nova (#681). No motor legado o lead fica como está; virada a conta, o
  # lead passa a mostrar a do Orth. O que cada lead acrescenta a lead_scoring fica guardado para results_metadata.
  def score_leads!(leads)
    assign_priority_positions!(leads)
    apply_score_engine!(leads)
  end

  def apply_score_engine!(leads)
    @score_engine = Autonomia::Prospecting::Scoring::SearchScoring.new(setting: @setting, mode: search_score_mode, filters: advanced_filters)
    @score_engine_scoring = @score_engine.apply!(leads)
  end

  def validate!
    # A tela mostra a frase como veio (#682): em :base, sem o nome do atributo em inglês na frente.
    raise ActiveRecord::RecordInvalid, search_with_error(:base, I18n.t('autonomia.prospecting.errors.query_required')) if query.blank?
    raise UnsupportedProviderError, I18n.t('autonomia.prospecting.errors.unsupported_provider') unless %w[mock google_places].include?(provider_name)
    raise ActiveRecord::RecordInvalid, search_with_error(:base, I18n.t('autonomia.prospecting.errors.limit_invalid')) if requested_limit <= 0

    validate_google_places! if provider_name == 'google_places'
    validate_drawn_area!

    if requested_limit > MAX_REQUESTED_LIMIT
      raise ActiveRecord::RecordInvalid, search_with_error(:base, I18n.t('autonomia.prospecting.errors.limit_too_high', max: MAX_REQUESTED_LIMIT))
    end

    validate_rank_range!
  end

  # O provider alcança no máximo MAX_REQUESTED_LIMIT posições (3 páginas de 20, #678). Cortar todas elas deixa a busca
  # sempre vazia e ainda gasta as chamadas ao Google (#677). Recusa antes de gravar busca ou cache.
  def validate_rank_range!
    outside_top = number_or_nil(advanced_filters['outside_top'])
    return if outside_top.nil? || outside_top < MAX_REQUESTED_LIMIT

    message = I18n.t('autonomia.prospecting.errors.rank_out_of_reach', limit: MAX_REQUESTED_LIMIT)
    raise ActiveRecord::RecordInvalid, search_with_error(:base, message)
  end

  # Área desenhada sem desenho que sirva (centro, limites ou três pontos) não vira busca (#678).
  def validate_drawn_area!
    return unless Autonomia::Prospecting::SearchArea.drawn?(area_type)
    return if Autonomia::Prospecting::SearchArea.normalize(area_type, raw_area_config, radius: radius)

    raise ActiveRecord::RecordInvalid, search_with_error(:base, I18n.t('autonomia.prospecting.errors.drawn_area_required'))
  end

  def create_search!
    Autonomia::Prospecting::Search.create!(
      account: @account,
      user: @user,
      query: query,
      location: location,
      radius: radius,
      area_type: area_type,
      area_config: area_config,
      provider: provider_name,
      requested_limit: requested_limit,
      status: :pending,
      cache_fingerprint: cache_fingerprint,
      cache_expires_at: cache_expires_at,
      categories: categories,
      metadata: metadata.merge(crm_target_metadata).merge(scoring_metadata)
    )
  end

  def provider(radius_value: radius, area_config_value: area_config)
    case provider_name
    when 'google_places'
      Autonomia::Prospecting::Providers::GooglePlacesProvider.new(
        query: query,
        location: location,
        radius: radius_value,
        area_type: area_type,
        area_config: area_config_value,
        limit: requested_limit,
        api_key: @setting.google_places_api_key,
        account_id: @account.id,
        country: search_country
      )
    else
      Autonomia::Prospecting::Providers::MockProvider.new(
        query: query,
        location: location,
        radius: radius_value,
        area_type: area_type,
        area_config: area_config_value,
        limit: requested_limit,
        country: search_country
      )
    end
  end

  # País da conta (#677): o Google busca e escreve o endereço nele, e o lead sem país no endereço fica com ele.
  def search_country
    @search_country ||= @setting.search_country
  end

  # Falha do Google depois da primeira página não descarta o que já chegou (#678): a busca termina com o que tem e fica
  # parcial. Só a primeira chamada da busca derruba tudo.
  def search_provider_results
    @consumed_api_units = 0
    last_attributes = []
    last_radius = radius
    partial = false

    (auto_expand_radius? ? expansion_radii : [radius]).each_with_index do |radius_value, index|
      attributes, partial = search_radius(radius_value, first: index.zero?)
      if use_radius_result?(attributes, partial, last_attributes)
        last_attributes = attributes
        last_radius = radius_value
      end
      break if partial || advanced_filtered_attributes_count(last_attributes) >= expansion_goal
    end

    {
      attributes: last_attributes,
      radius: last_radius,
      api_units: @consumed_api_units,
      partial: partial
    }
  end

  # Raio maior completo sempre substitui o anterior. Parcial só substitui se trouxe pelo menos tantos lugares que passam
  # nos filtros quanto o raio anterior.
  def use_radius_result?(attributes, partial, last_attributes)
    return false if attributes.nil?
    return true unless partial

    advanced_filtered_attributes_count(attributes) >= advanced_filtered_attributes_count(last_attributes)
  end

  # [lugares, parcial]. Lugares nil quando o raio maior falhou já na primeira página e a busca fica com o raio anterior.
  def search_radius(radius_value, first:)
    provider_instance = provider(radius_value: radius_value, area_config_value: area_config_for_radius(radius_value))
    attributes = provider_instance.search(max_results: last_reachable_rank) do |item, google_rank|
      advanced_filter_matches?(item, google_rank)
    end
    [attributes, provider_instance.try(:partial?) || false]
  rescue ProviderError
    raise if first

    [nil, true]
  ensure
    @consumed_api_units += provider_instance.try(:api_units).to_i
  end

  # Última posição que vale ler: depois de search_rank_max o filtro descarta tudo, então as páginas seguintes seriam
  # chamadas pagas à toa (#678).
  def last_reachable_rank
    search_rank_max = number_or_nil(advanced_filters['search_rank_max'])
    search_rank_max ? search_rank_max.to_i.clamp(0, MAX_REQUESTED_LIMIT) : MAX_REQUESTED_LIMIT
  end

  # O raio só cresce enquanto falta lugar para o pedido. A faixa de posição corta as mesmas posições em qualquer raio,
  # então o que ela tira não é falta que raio maior resolva: sem descontar, a meta nunca era alcançada e a busca
  # expandia sempre até 4x (#677).
  def expansion_goal
    outside_top = number_or_nil(advanced_filters['outside_top']).to_i

    [requested_limit, last_reachable_rank - outside_top].min
  end

  # Falta de chave é da plataforma, não de quem busca: o detalhe vai para o log e a pessoa lê a frase em português.
  def validate_google_places!
    return if @setting.google_places_configured?

    Rails.logger.warn("[Prospecting::GooglePlaces] search account_id=#{@account.id} GOOGLE_PLACES_API_KEY não configurada")
    raise ProviderError, I18n.t('autonomia.prospecting.errors.google_unavailable')
  end

  # Grava na ordem da chave do lead, não na do Google: duas buscas simultâneas com os mesmos lugares em ordem diferente
  # travariam as linhas em ordem cruzada, e o Postgres derruba uma delas por deadlock (#683). O resultado volta na ordem
  # do Google.
  def upsert_leads!(search, filtered_attributes)
    filtered_attributes.sort_by { |attributes, _google_rank| dedupe_key_for(attributes) }
                       .map { |attributes, google_rank| upsert_lead!(search, attributes, google_rank: google_rank) }
                       .sort_by(&:search_rank)
  end

  # Duas buscas sobre o mesmo lugar podem ler "não existe" ao mesmo tempo. Quem perde a corrida no índice único
  # relê o lead que a outra gravou e atualiza em cima dele. O savepoint impede que o insert recusado aborte a
  # transação da busca inteira (#683).
  def upsert_lead!(search, attributes, google_rank:)
    dedupe_key = dedupe_key_for(attributes)
    retried = false
    begin
      Autonomia::Prospecting::Lead.transaction(requires_new: true) { save_lead!(search, attributes, dedupe_key, google_rank) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if retried || !lost_race?(e)

      retried = true
      retry
    end
  end

  # O lead é um só por conta e o search_rank dele é o da busca mais recente. A busca guarda a posição de cada lead
  # dela, para o card e o refino por faixa de posição ao reabrir (#677).
  def lead_ranks(leads)
    leads.to_h { |lead| [lead.id.to_s, lead.search_rank] }
  end

  # Nota, detalhe da nota e prioridade também são da busca (#678): a posição de prioridade só faz sentido entre os
  # leads da mesma busca, e a nota muda com o modo e a posição no Google dela.
  def lead_scoring(leads)
    leads.to_h do |lead|
      [
        lead.id.to_s,
        {
          'score' => lead.score&.to_f,
          'score_breakdown' => lead.score_breakdown,
          'priority_score' => lead.priority_score&.to_f,
          'priority_position' => lead.priority_position
        }.merge(@score_engine_scoring.to_h.fetch(lead.id.to_s, {}))
      ]
    end
  end

  def lost_race?(error)
    error.is_a?(ActiveRecord::RecordNotUnique) || error.record.errors.of_kind?(:dedupe_key, :taken)
  end

  def save_lead!(search, attributes, dedupe_key, google_rank)
    lead = find_existing_lead(attributes, dedupe_key) || Autonomia::Prospecting::Lead.new(account: @account)
    scoring_attributes = score_for(attributes, google_rank)
    new_metadata = attributes[:metadata].to_h
    existing = lead.persisted?
    previous_phone = lead.phone
    # Pelo id, não pelo objeto: com o objeto, o inverse_of põe o lead em search.leads, e o lead recusado na corrida
    # (ou inválido) ficaria ali e derrubaria o save! da própria busca.
    lead.assign_attributes(
      attributes.except(:metadata).merge(scoring_attributes)
                .merge(prospect_search_id: search.id, dedupe_key: dedupe_key, search_rank: google_rank)
    )
    lead.metadata = lead.metadata.to_h.merge(new_metadata) unless existing
    lead.save!
    merge_lead_metadata!(lead, new_metadata, previous_phone: previous_phone) if existing
    lead
  end

  # A verificação de WhatsApp é do número verificado, não do lead (ENRIQ-69): com outro telefone ela deixa de valer,
  # e sem ela o lead volta à fila de verificação (LeadWorkQueue.after_search). Mesmo número escrito de outro jeito
  # continua valendo (E.164); a marca "queued" fica, e o verificador devolve à fila se o número mudou no meio. A
  # verificação sem o número dela (antiga) vale enquanto o telefone do lead não muda.
  def merge_lead_metadata!(lead, new_metadata, previous_phone:)
    new_e164 = phone_e164(lead.phone)
    assumed_phone = new_e164 == phone_e164(previous_phone) ? new_e164 : ''
    scope = Autonomia::Prospecting::Lead.where(id: lead.id)
    scope.update_all([METADATA_MERGE_SQL, assumed_phone, new_e164, new_metadata.to_json]) # rubocop:disable Rails/SkipsModelValidations
    lead.metadata = scope.pick(:metadata)
    lead.clear_attribute_changes([:metadata])
  end

  def phone_e164(phone)
    Autonomia::Prospecting::PhoneContract.e164(phone, region: phone_region)
  end

  def phone_region
    @phone_region ||= Autonomia::Prospecting::PhoneContract.region_for(@account)
  end

  def score_for(attributes, google_rank)
    Autonomia::Prospecting::LeadScorer.new(
      lead_attributes: attributes,
      query: query,
      google_rank: google_rank,
      weights: @setting.active_scoring_weights,
      score_mode: search_score_mode
    ).perform
  end

  def assign_priority_positions!(leads)
    ranked_priority(leads.compact).each do |item|
      item[:lead].update_columns(
        priority_score: item[:priority_score],
        priority_position: item[:priority_position]
      )
      item[:lead].priority_score = item[:priority_score]
      item[:lead].priority_position = item[:priority_position]
    end
  end

  def ranked_priority(leads)
    return [] if leads.blank?

    ranked = leads.map do |lead|
      raw_priority = (lead.score.to_f * priority_multiplier(lead)) - priority_penalty(lead)
      { lead: lead, raw_priority: raw_priority }
    end

    percentiles = priority_percentiles(ranked)
    ranked.map do |item|
      item.merge(priority_score: percentiles[item[:raw_priority]].to_f.round)
    end.sort_by do |item|
      [
        -item[:priority_score].to_f,
        -item[:lead].score.to_f,
        item[:lead].search_rank.to_i.positive? ? item[:lead].search_rank.to_i : Float::INFINITY,
        item[:lead].name.to_s
      ]
    end.each_with_index.map do |item, index|
      item.merge(priority_position: index + 1)
    end
  end

  def priority_percentiles(ranked)
    sorted = ranked.sort_by { |item| item[:raw_priority] }
    return { sorted.first[:raw_priority] => 100 } if sorted.one?

    sorted.each_with_index.each_with_object({}) do |(item, index), memo|
      percentile = (index.to_f / (sorted.size - 1) * 100).round
      memo[item[:raw_priority]] = [memo[item[:raw_priority]].to_i, percentile].max
    end
  end

  def priority_multiplier(lead)
    contactability = lead.phone.present? ? 1.0 : 0.3
    contactability = 1.3 if lead.metadata.to_h.dig('whatsapp_verification', 'status') == 'verified'
    decisor = research_decision?(lead) ? 1.2 : 1.0
    hour = lead.raw_payload.to_h.dig('currentOpeningHours', 'openNow') == true ? 1.15 : 1.0

    contactability * decisor * hour
  end

  # O decisor que sobe a prioridade é o que a tela mostra (#679): o da pesquisa, confirmado ou possível. O nome gravado
  # antes dela fica no lead, mas não conta.
  def research_decision?(lead)
    lead.decision_name.present? &&
      Autonomia::Prospecting::Research::Payload::FOUND.include?(lead.decision_research_status)
  end

  def priority_penalty(lead)
    Array(lead.negative_factors).size * 3
  end

  def find_existing_lead(attributes, dedupe_key)
    scope = Autonomia::Prospecting::Lead.where(account: @account)

    if attributes[:provider_place_id].present?
      existing = scope.find_by(provider: attributes[:provider], provider_place_id: attributes[:provider_place_id])
      return existing if existing
    end

    scope.find_by(dedupe_key: dedupe_key)
  end

  def dedupe_key_for(attributes)
    [
      attributes[:provider],
      attributes[:provider_place_id].presence ||
        attributes[:phone].presence ||
        attributes[:website].presence ||
        attributes[:name]
    ].join(':').downcase
  end

  def query
    @query ||= @params[:query].to_s.strip
  end

  def location
    @location ||= @params[:location].to_s.strip
  end

  def radius
    @radius ||= @params[:radius].presence&.to_i || 1000
  end

  def area_type
    @area_type ||= begin
      requested_type = @params[:area_type].to_s
      AREA_TYPES.include?(requested_type) ? requested_type : 'radius'
    end
  end

  def area_config
    @area_config ||= normalized_area_config
  end

  def area_config_for_radius(radius_value)
    return area_config unless area_type == 'radius'

    area_config.merge('radius' => radius_value)
  end

  def search_filters
    @search_filters ||= begin
      filters = metadata['filters'].presence || @params[:filters].presence || {}
      filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
      filters = filters.to_h if filters.respond_to?(:to_h)
      filters.deep_stringify_keys.slice('auto_expand_radius')
    end
  end

  def advanced_filters
    @advanced_filters ||= begin
      filters = metadata['advanced_filters'].presence || @params[:advanced_filters].presence || {}
      filters = filters.to_unsafe_h if filters.respond_to?(:to_unsafe_h)
      filters = filters.to_h if filters.respond_to?(:to_h)
      filters.deep_stringify_keys
    end
  end

  # Chaves e regras da gaveta de filtros do Orth (search-filters.ts). has_photos, open_now e has_opening_hours são
  # atributos que o provider entrega (contrato #677); sem eles o filtro ativo falha alto em vez de zerar a busca.
  # O recorte do polígono (#678) entra aqui: roda depois de a posição no Google já estar atribuída pelo índice.
  def advanced_filter_matches?(attributes, google_rank)
    within_drawn_area?(attributes) && presence_filters_match?(attributes) && rating_filters_match?(attributes) && rank_filters_match?(google_rank) &&
      reviews_filter_matches?(attributes)
  end

  def within_drawn_area?(attributes)
    Autonomia::Prospecting::SearchArea.contains?(area_type, area_config, attributes[:latitude], attributes[:longitude])
  end

  def presence_filters_match?(attributes)
    boolean_filter_matches?(attributes[:website], advanced_filters['has_website']) &&
      boolean_filter_matches?(attributes[:phone], advanced_filters['has_phone']) &&
      photos_filter_matches?(attributes) &&
      only_yes_filter_matches?(attributes, :open_now) &&
      only_yes_filter_matches?(attributes, :has_opening_hours)
  end

  # "Acima de" descarta quem não tem nota; "abaixo de" deixa passar, como no Orth.
  def rating_filters_match?(attributes)
    rating = number_or_nil(attributes[:rating])
    rating_min = number_or_nil(advanced_filters['rating_min'])
    return false if rating_min && (rating.nil? || rating < rating_min)

    rating_max = number_or_nil(advanced_filters['rating_max'])
    !(rating_max && rating && rating > rating_max)
  end

  # Faixa da posição no Google: outside_top corta as N primeiras, search_rank_max corta depois da N-ésima.
  def rank_filters_match?(google_rank)
    outside_top = number_or_nil(advanced_filters['outside_top'])
    return false if outside_top && google_rank <= outside_top

    search_rank_max = number_or_nil(advanced_filters['search_rank_max'])
    !(search_rank_max && google_rank > search_rank_max)
  end

  def reviews_filter_matches?(attributes)
    reviews_min = number_or_nil(advanced_filters['reviews_min'])
    !(reviews_min && attributes[:reviews_count].to_i < reviews_min)
  end

  def photos_filter_matches?(attributes)
    filter_value = advanced_filters['has_photos']
    return true if filter_value.blank?

    attributes.fetch(:has_photos) == (filter_value == 'yes')
  end

  # Aberto agora e tem horário só têm a opção "sim", como no Orth. Outro valor não filtra.
  def only_yes_filter_matches?(attributes, key)
    return true unless advanced_filters[key.to_s] == 'yes'

    attributes.fetch(key) == true
  end

  def advanced_filtered_attributes_count(attributes)
    attributes.each_with_index.count do |item, index|
      advanced_filter_matches?(item, index + 1)
    end
  end

  def boolean_filter_matches?(value, filter_value)
    return true if filter_value.blank?

    filter_value == 'yes' ? value.present? : value.blank?
  end

  def number_or_nil(value)
    return if value.blank?

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def auto_expand_radius?
    area_type == 'radius' &&
      ActiveModel::Type::Boolean.new.cast(search_filters['auto_expand_radius'])
  end

  def expansion_radii
    [
      radius,
      [radius * 2, 50_000].min,
      [radius * 4, 50_000].min
    ].uniq
  end

  def provider_name
    @provider_name ||= @setting.provider.presence || 'mock'
  end

  def requested_limit
    @requested_limit ||= (@params[:requested_limit].presence || @params[:limit].presence || @setting.default_limit).to_i
  end

  def categories
    Array(@params[:categories]).compact_blank
  end

  def metadata
    @metadata ||= begin
      raw_metadata = @params[:metadata].presence || {}
      raw_metadata = raw_metadata.to_unsafe_h if raw_metadata.respond_to?(:to_unsafe_h)
      raw_metadata = raw_metadata.to_h if raw_metadata.respond_to?(:to_h)
      normalize_location_coordinates(raw_metadata.deep_stringify_keys)
    end
  end

  # Coordinates arrive as Float from JSON clients and as String from form-encoded
  # clients; persist them as numbers so the stored metadata (and the API payload
  # built from it) does not depend on the request transport.
  def normalize_location_coordinates(hash)
    LOCATION_COORDINATE_KEYS.each_with_object(hash.dup) do |key, normalized|
      normalized[key] = numeric_value(hash[key]) if hash.key?(key)
    end
  end

  def raw_area_config
    @raw_area_config ||= begin
      raw_config = @params[:area_config].presence || {}
      raw_config = raw_config.to_unsafe_h if raw_config.respond_to?(:to_unsafe_h)
      raw_config = raw_config.to_h if raw_config.respond_to?(:to_h)
      raw_config.deep_stringify_keys
    end
  end

  def normalized_area_config
    base = {
      'label' => metadata['location_label'].presence || location.presence,
      'place_id' => metadata['location_place_id'].presence
    }.compact
    geometry = if Autonomia::Prospecting::SearchArea.drawn?(area_type)
                 Autonomia::Prospecting::SearchArea.normalize(area_type, raw_area_config, radius: radius).to_h
               else
                 located_area_config(raw_area_config)
               end
    base.merge(geometry)
  end

  # Raio e área visível: a área parte do local escolhido.
  def located_area_config(raw_config)
    center = normalize_center(raw_config['center']) || metadata_center

    if area_type == 'viewport'
      bounds = normalize_bounds(raw_config['bounds'])
      center ||= center_from_bounds(bounds)

      return { 'bounds' => bounds, 'center' => center, 'radius' => radius }.compact
    end

    { 'center' => center, 'radius' => radius }.compact
  end

  def metadata_center
    lat = metadata['location_latitude'].presence
    lng = metadata['location_longitude'].presence
    normalize_center('lat' => lat, 'lng' => lng)
  end

  def normalize_center(value)
    return if value.blank?

    hash = value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : {}
    lat = numeric_value(hash['lat'] || hash['latitude'])
    lng = numeric_value(hash['lng'] || hash['longitude'])
    return if lat.nil? || lng.nil?

    { 'lat' => lat, 'lng' => lng }
  end

  def normalize_bounds(value)
    return if value.blank?

    hash = value.respond_to?(:to_h) ? value.to_h.deep_stringify_keys : {}
    north = numeric_value(hash['north'])
    south = numeric_value(hash['south'])
    east = numeric_value(hash['east'])
    west = numeric_value(hash['west'])
    return if [north, south, east, west].any?(&:nil?)

    {
      'north' => [north, south].max,
      'south' => [north, south].min,
      'east' => east,
      'west' => west
    }
  end

  def center_from_bounds(bounds)
    return if bounds.blank?

    {
      'lat' => ((bounds['north'].to_f + bounds['south'].to_f) / 2.0).round(6),
      'lng' => ((bounds['east'].to_f + bounds['west'].to_f) / 2.0).round(6)
    }
  end

  def numeric_value(value)
    return if value.blank?

    Float(value).round(6)
  rescue ArgumentError, TypeError
    nil
  end

  def crm_target_metadata
    {
      'crm_pipeline_id' => crm_pipeline_id,
      'crm_stage_id' => crm_stage_id
    }.compact
  end

  # Modo, jogada e decisor da busca (#677). A jogada é gravada mesmo nula, para
  # sobrescrever o valor cru do pedido depois de validada contra o modo.
  def scoring_metadata
    {
      'score_mode' => search_score_mode,
      'scoring_profile_id' =>
        metadata['scoring_profile_id'].presence || @setting.scoring_profile_id
    }.compact.merge(
      'preset_id' => search_preset_id,
      'decision_maker_type' => Autonomia::Prospecting::DecisionMakerType.normalize(metadata['decision_maker_type'])
    )
  end

  def search_preset_id
    preset_id = metadata['preset_id'].presence
    return if preset_id.nil?
    return preset_id.to_s if Autonomia::Prospecting::SearchPresets.valid_for?(account: @account, preset_id: preset_id, score_mode: search_score_mode)

    raise ActiveRecord::RecordInvalid, search_with_error(:base, I18n.t('autonomia.prospecting.presets.invalid'))
  end

  def search_score_mode
    @search_score_mode ||= begin
      value = metadata['score_mode'].presence || @setting.search_score_mode
      %w[gbp general].include?(value.to_s) ? value.to_s : 'gbp'
    end
  end

  def fresh?
    ActiveModel::Type::Boolean.new.cast(@params[:fresh]) == true
  end

  def cached_result
    return if @setting.cache_ttl_seconds.to_i <= 0

    # Só busca concluída serve de cache: a que falhou nasceu com a mesma impressão digital e devolveria vazio (#683).
    search = Autonomia::Prospecting::Search
             .completed
             .where(account: @account, provider: provider_name, cache_fingerprint: cache_fingerprint)
             .where('cache_expires_at > ?', Time.current)
             .order(created_at: :desc)
             .first
    return if search.blank?

    lead_ids = Array(search.metadata.to_h['lead_ids']).map(&:to_i)
    leads = Autonomia::Prospecting::Lead.where(account: @account, id: lead_ids).index_by(&:id).values_at(*lead_ids).compact
    cached_search = Autonomia::Prospecting::Search.create!(
      account: @account,
      user: @user,
      query: query,
      location: location,
      radius: search.radius,
      area_type: search.area_type,
      area_config: search.area_config,
      provider: provider_name,
      requested_limit: requested_limit,
      status: :cached,
      consumed_api_units: 0,
      cache_fingerprint: cache_fingerprint,
      cache_expires_at: search.cache_expires_at,
      categories: categories,
      metadata: metadata.merge(crm_target_metadata)
                        .merge(scoring_metadata).merge(
                          'lead_ids' => leads.map(&:id),
                          'lead_ranks' => search.metadata.to_h['lead_ranks'],
                          'lead_scoring' => search.metadata.to_h['lead_scoring'],
                          'results_count' => leads.size,
                          'cached_from_search_id' => search.id,
                          'search_filters' => search_filters,
                          # O raio gravado é o que a busca de origem alcançou; Repetir precisa do que a pessoa pediu (#678).
                          'requested_radius' => radius,
                          'radius_expanded' => search.metadata.to_h['radius_expanded'] == true
                        )
    )

    Result.new(search: cached_search, leads: leads)
  end

  def cache_fingerprint
    @cache_fingerprint ||= Digest::SHA256.hexdigest(
      [
        @account.id,
        provider_name,
        query.downcase,
        location.downcase,
        radius,
        area_type,
        JSON.generate(area_config),
        JSON.generate(search_filters),
        JSON.generate(advanced_filters),
        requested_limit,
        search_score_mode,
        search_country,
        *scoring_cache_parts
      ].join(':')
    )
  end

  # Busca feita num motor não serve de cache para o outro. O motor legado não entra na impressão digital, para o cache
  # que já existe continuar valendo (#681).
  def scoring_cache_parts
    parts = [@setting.scoring_mode, @setting.scoring_profile_id, @setting.active_scoring_weights.sort.to_h]
    @setting.orth_score_engine? ? parts + ['score_engine:orth'] : parts
  end

  def cache_expires_at
    return if @setting.cache_ttl_seconds.to_i <= 0

    Time.current + @setting.cache_ttl_seconds.to_i.seconds
  end

  def search_with_error(attribute, message)
    search = Autonomia::Prospecting::Search.new
    search.errors.add(attribute, message)
    search
  end

  def crm_pipeline_id
    @crm_pipeline_id ||= @params[:crm_pipeline_id].presence || @setting.default_crm_pipeline_id
  end

  def crm_stage_id
    @crm_stage_id ||= @params[:crm_stage_id].presence || @setting.default_crm_stage_id
  end
end
