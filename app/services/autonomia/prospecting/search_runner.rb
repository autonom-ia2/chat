require 'digest'
require 'json'

class Autonomia::Prospecting::SearchRunner
  AREA_TYPES = %w[radius viewport].freeze
  LOCATION_COORDINATE_KEYS = %w[location_latitude location_longitude].freeze

  Result = Struct.new(:search, :leads, keyword_init: true)

  class UnsupportedProviderError < StandardError; end
  class ProviderError < StandardError; end

  def initialize(account:, user:, params:)
    @account = account
    @user = user
    @params = params.to_h.symbolize_keys
    @setting = Autonomia::Prospecting::Setting.for_account(account)
  end

  def perform
    validate!
    cached = cached_result
    return cached if cached
    validate_usage_limits!

    search = create_search!
    leads = []

    ActiveRecord::Base.transaction do
      provider_result = search_provider_results
      filtered_attributes = provider_result[:attributes].each_with_index.filter_map do |attributes, index|
        google_rank = index + 1
        next unless advanced_filter_matches?(attributes, google_rank)

        [attributes, google_rank]
      end
      leads = filtered_attributes.map do |attributes, google_rank|
        upsert_lead!(search, attributes, google_rank: google_rank)
      end
      assign_priority_positions!(leads)
      search.radius = provider_result[:radius]
      search.area_config = area_config_for_radius(provider_result[:radius])
      search.metadata = search.metadata.to_h.merge(
        'lead_ids' => leads.map(&:id),
        'results_count' => leads.size,
        'search_filters' => search_filters,
        'requested_radius' => radius,
        'radius_expanded' => provider_result[:radius].to_i > radius
      )
      search.status = :completed
      search.consumed_api_units = provider_result[:api_units]
      search.cache_fingerprint = cache_fingerprint
      search.cache_expires_at = cache_expires_at
      search.save!
    end

    Result.new(search: search.reload, leads: leads)
  rescue StandardError => e
    search&.update!(status: :failed, metadata: search.metadata.to_h.merge('error' => e.message)) if search&.persisted?
    raise
  end

  private

  def validate!
    raise ActiveRecord::RecordInvalid.new(search_with_error(:query, "can't be blank")) if query.blank?
    raise UnsupportedProviderError, 'Unsupported prospecting provider' unless %w[mock google_places].include?(provider_name)
    raise ActiveRecord::RecordInvalid.new(search_with_error(:requested_limit, 'must be greater than 0')) if requested_limit <= 0
    validate_google_places! if provider_name == 'google_places'

    return if requested_limit <= @setting.max_results_per_search

    raise ActiveRecord::RecordInvalid.new(
      search_with_error(:requested_limit, "must be less than or equal to #{@setting.max_results_per_search}")
    )
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
        api_key: @setting.google_places_api_key
      )
    else
      Autonomia::Prospecting::Providers::MockProvider.new(
        query: query,
        location: location,
        radius: radius_value,
        area_type: area_type,
        area_config: area_config_value,
        limit: requested_limit
      )
    end
  end

  def search_provider_results
    radii = auto_expand_radius? ? expansion_radii : [radius]
    api_units = 0
    last_attributes = []
    last_radius = radius

    radii.each do |radius_value|
      provider_instance = provider(
        radius_value: radius_value,
        area_config_value: area_config_for_radius(radius_value)
      )
      last_attributes = provider_instance.search
      last_radius = radius_value
      api_units += if provider_instance.respond_to?(:api_units)
                     provider_instance.api_units.to_i
                   else
                     0
                   end
      break if advanced_filtered_attributes_count(last_attributes) >= requested_limit
    end

    {
      attributes: last_attributes,
      radius: last_radius,
      api_units: api_units
    }
  end

  def validate_google_places!
    raise ProviderError, 'Google Places provider is disabled for this account' unless @setting.provider_enabled?
    raise ProviderError, 'Google Places API key is not configured for this account' unless @setting.google_places_configured?
  end

  def upsert_lead!(search, attributes, google_rank:)
    dedupe_key = dedupe_key_for(attributes)
    lead = find_existing_lead(attributes, dedupe_key) || Autonomia::Prospecting::Lead.new(account: @account)
    scoring_attributes = score_for(attributes, google_rank)
    lead_metadata = lead.metadata.to_h.merge(attributes[:metadata].to_h)
    lead.assign_attributes(
      attributes.merge(scoring_attributes).merge(search: search, dedupe_key: dedupe_key, search_rank: google_rank, metadata: lead_metadata)
    )
    lead.save!
    lead
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
      raw_priority = lead.score.to_f * priority_multiplier(lead) - priority_penalty(lead)
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
    decisor = lead.decision_name.present? ? 1.2 : 1.0
    hour = lead.raw_payload.to_h.dig('currentOpeningHours', 'openNow') == true ? 1.15 : 1.0

    contactability * decisor * hour
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

  def advanced_filter_matches?(attributes, google_rank)
    return false unless boolean_filter_matches?(attributes[:website], advanced_filters['has_website'])
    return false unless boolean_filter_matches?(attributes[:phone], advanced_filters['has_phone'])
    return false unless boolean_filter_matches?(attributes[:has_photos], advanced_filters['has_photos'])
    return false unless optional_boolean_filter_matches?(attributes[:open_now], advanced_filters['open_now'])

    rating = number_or_nil(attributes[:rating])
    rating_min = number_or_nil(advanced_filters['rating_min'])
    return false if rating_min && (rating.nil? || rating < rating_min)

    rating_max = number_or_nil(advanced_filters['rating_max'])
    return false if rating_max && (rating.nil? || rating > rating_max)

    reviews_min = number_or_nil(advanced_filters['reviews_min'])
    return false if reviews_min && attributes[:reviews_count].to_i < reviews_min

    search_rank_max = number_or_nil(advanced_filters['search_rank_max'])
    return false if search_rank_max && google_rank > search_rank_max

    true
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

  def optional_boolean_filter_matches?(value, filter_value)
    return true if filter_value.blank?
    return false if value.nil?

    filter_value == 'yes' ? value == true : value == false
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

  def normalized_area_config
    raw_config = @params[:area_config].presence || {}
    raw_config = raw_config.to_unsafe_h if raw_config.respond_to?(:to_unsafe_h)
    raw_config = raw_config.to_h if raw_config.respond_to?(:to_h)
    raw_config = raw_config.deep_stringify_keys

    center = normalize_center(raw_config['center']) || metadata_center
    base = {
      'label' => metadata['location_label'].presence || location.presence,
      'place_id' => metadata['location_place_id'].presence
    }.compact

    if area_type == 'viewport'
      bounds = normalize_bounds(raw_config['bounds'])
      center ||= center_from_bounds(bounds)

      return base.merge(
        {
          'bounds' => bounds,
          'center' => center,
          'radius' => radius
        }.compact
      )
    end

    base.merge(
      {
        'center' => center,
        'radius' => radius
      }.compact
    )
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

  def scoring_metadata
    {
      'score_mode' => search_score_mode,
      'scoring_profile_id' =>
        metadata['scoring_profile_id'].presence || @setting.scoring_profile_id
    }.compact
  end

  def search_score_mode
    @search_score_mode ||= begin
      value = metadata['score_mode'].presence || @setting.search_score_mode
      %w[gbp general].include?(value.to_s) ? value.to_s : 'gbp'
    end
  end

  def cached_result
    return if @setting.cache_ttl_seconds.to_i <= 0

    search = Autonomia::Prospecting::Search
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
        'results_count' => leads.size,
        'cached_from_search_id' => search.id,
        'search_filters' => search_filters
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
        @setting.scoring_mode,
        @setting.scoring_profile_id,
        @setting.active_scoring_weights.sort.to_h
      ].join(':')
    )
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

  def validate_usage_limits!
    return if estimated_api_units.zero?

    validate_usage_limit!(:daily_limit, Time.current.beginning_of_day)
    validate_usage_limit!(:monthly_limit, Time.current.beginning_of_month)
  end

  def validate_usage_limit!(limit_attribute, period_start)
    limit = @setting.public_send(limit_attribute).to_i
    return if limit <= 0

    usage = Autonomia::Prospecting::Search
            .where(account: @account)
            .where('created_at >= ?', period_start)
            .sum(:consumed_api_units)
    return if usage + estimated_api_units <= limit

    raise ProviderError, "#{limit_attribute.to_s.humanize} exceeded for prospecting"
  end

  def estimated_api_units
    @estimated_api_units ||= if provider_name == 'google_places'
                               auto_expand_radius? ? expansion_radii.size : 1
                             else
                               0
                             end
  end

  def crm_pipeline_id
    @crm_pipeline_id ||= @params[:crm_pipeline_id].presence || @setting.default_crm_pipeline_id
  end

  def crm_stage_id
    @crm_stage_id ||= @params[:crm_stage_id].presence || @setting.default_crm_stage_id
  end
end
