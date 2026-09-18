class EmailCampaigns::Reports::Parameters
  class Invalid < StandardError
    attr_reader :parameter

    def initialize(parameter)
      @parameter = parameter
      super('email_campaign.invalid_filter')
    end
  end

  PER_PAGE = 50
  MAX_PAGE = 1_000_000
  attr_reader :values

  def initialize(params, allowed:)
    @values = params.to_h.stringify_keys.slice(*allowed.map(&:to_s))
  end

  def text(key, max: 320)
    value = values[key.to_s]
    return if value.nil?

    raise Invalid, key unless value.is_a?(String) && value.length <= max

    value.strip.presence
  end

  def choice(key, choices)
    value = text(key)
    raise Invalid, key if value && choices.exclude?(value)

    value
  end

  def page
    positive_integer('page', default: 1, max: MAX_PAGE)
  end

  def positive_integer(key, default: nil, max: 9_223_372_036_854_775_807)
    value = values[key.to_s]
    return default if value.nil?

    raise Invalid, key unless value.to_s.match?(/\A[1-9][0-9]{0,18}\z/) && value.to_s.to_i <= max

    value.to_s.to_i
  end

  def boolean(key)
    value = values[key.to_s]
    return if value.nil?
    return true if [true, 'true', '1', 1].include?(value)
    return false if [false, 'false', '0', 0].include?(value)

    raise Invalid, key
  end

  def self.meta(count, page, filters)
    { count: count, current_page: page, per_page: PER_PAGE, total_pages: (count.to_f / PER_PAGE).ceil,
      applied_filters: filters }
  end
end
