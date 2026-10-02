# Shared read-only projection for contact/company profiles. Authentication,
# record authorization and card visibility remain the responsibility of each caller.
class Api::V1::Accounts::Crm::ProfileOpportunitiesController < Api::V1::Accounts::Crm::BaseController
  RESULTS_PER_PAGE = 5
  RESULTS = %w[active all open won lost archived].freeze

  private

  def render_opportunities(cards, include_contact: false)
    cards = filter_cards(cards)
    total = cards.count
    associations = [:pipeline, :stage, :owner]
    associations << :contact if include_contact
    rows = cards.reorder(updated_at: :desc, id: :desc).offset((@page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE).preload(*associations)
    payload = rows.map do |card|
      row = card_payload(card)
      row[:contact] = card.contact&.slice(:id, :name) if include_contact
      row
    end
    render json: { payload: payload, meta: { total_count: total, page: @page, per_page: RESULTS_PER_PAGE,
                                             has_more: @page * RESULTS_PER_PAGE < total } }
  end

  def valid_parameters?(record_id)
    @record_id = positive_id(record_id)
    @page = positive_id(params.fetch(:page, '1'))
    @result = params.fetch(:result, 'active')
    @search = params.fetch(:search, '')
    @record_id && @page && RESULTS.include?(@result) && @search.is_a?(String) && @search.length <= 200
  end

  def positive_id(value)
    return unless value.is_a?(String)

    id = Integer(value, 10, exception: false)
    id if id&.positive? && id.to_s == value && id <= 9_007_199_254_740_991
  end

  def filter_cards(cards)
    cards = cards.where.not(status: :archived) if @result == 'active'
    cards = cards.where(status: @result) unless %w[active all].include?(@result)
    return cards if @search.strip.empty?

    search = ActiveRecord::Base.sanitize_sql_like(@search.strip.downcase)
    cards.where('LOWER(crm_cards.title) LIKE ?', "%#{search}%")
  end

  def card_payload(card)
    card.slice(:id, :title, :status, :value_cents, :currency, :expected_close_at).merge(
      pipeline: card.pipeline.slice(:id, :name), stage: card.stage.slice(:id, :name), owner: card.owner&.slice(:id, :name)
    )
  end
end
