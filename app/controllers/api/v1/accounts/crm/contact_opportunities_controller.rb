# Read-only projection for the shared contact profile. Never serialize messages,
# conversation identifiers, AI metadata or contact fields through this endpoint.
class Api::V1::Accounts::Crm::ContactOpportunitiesController < Api::V1::Accounts::Crm::BaseController
  RESULTS_PER_PAGE = 5
  RESULTS = %w[active all open won lost archived].freeze

  def index
    authorize ::Crm::Card, :index?
    return render_unprocessable('crm.contact_opportunities.invalid_parameters') unless valid_parameters?

    contact = Current.account.contacts.find(@contact_id)
    authorize contact, :show?
    cards = policy_scope(::Crm::Card).where(account_id: Current.account.id, contact_id: contact.id)
    cards = filter_cards(cards)
    total = cards.count
    rows = cards.reorder(updated_at: :desc, id: :desc).offset((@page - 1) * RESULTS_PER_PAGE).limit(RESULTS_PER_PAGE)
                .preload(:pipeline, :stage, :owner)
    render json: { payload: rows.map { |card| card_payload(card) },
                   meta: { total_count: total, page: @page, per_page: RESULTS_PER_PAGE, has_more: @page * RESULTS_PER_PAGE < total } }
  end

  private

  def valid_parameters?
    @contact_id = positive_id(params[:contact_id])
    @page = positive_id(params.fetch(:page, '1'))
    @result = params.fetch(:result, 'active')
    @search = params.fetch(:search, '')
    @contact_id && @page && RESULTS.include?(@result) && @search.is_a?(String) && @search.length <= 200
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
      pipeline: card.pipeline.slice(:id, :name),
      stage: card.stage.slice(:id, :name),
      owner: card.owner&.slice(:id, :name)
    )
  end
end
