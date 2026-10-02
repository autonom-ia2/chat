module Crm::FilterParameters
  extend ActiveSupport::Concern

  SCORE_FILTER_KEYS = %i[score_min score_max].freeze

  private

  def validate_crm_filter_parameters
    return if valid_company_filter_param? && valid_score_range_params?

    render_unprocessable('crm.invalid_filter_parameters')
  end

  def valid_company_filter_param?
    return true unless params.key?(:company_id)

    raw_company_id = params[:company_id]
    return true if raw_company_id == 'none'

    company_id = integer_filter_param(raw_company_id)
    company_id.present? && company_id.positive?
  end

  def valid_score_range_params?
    return true unless score_filter_present?

    valid_score_bounds? && valid_score_order?
  end

  def score_filter_present?
    SCORE_FILTER_KEYS.any? { |key| params.key?(key) }
  end

  def valid_score_bounds?
    values = score_filter_values
    SCORE_FILTER_KEYS.all? { |key| !params.key?(key) || values[key].present? }
  end

  def valid_score_order?
    score_filter_values.values.compact.each_cons(2).all? { |minimum, maximum| minimum <= maximum }
  end

  def score_filter_values
    SCORE_FILTER_KEYS.index_with { |key| score_filter_value(key) }
  end

  def score_filter_value(key)
    raw_value = params[key]
    value = integer_filter_param(raw_value)
    value if value&.between?(0, 100)
  end

  def integer_filter_param(raw_value)
    return raw_value if raw_value.is_a?(Integer)
    return unless raw_value.is_a?(String)

    value = Integer(raw_value, 10, exception: false)
    value if value&.to_s == raw_value
  end
end
