# Returns grouped totals (count + Σ value) for the CRM list view's "Group by"
# headers. Lives under cards/ so it shares the crm namespace authorization and
# the same FilterQuery contract as the cards index — the summary is always
# computed over the identical filtered + policy-scoped row set the list renders.
#
#   GET .../crm/cards/summaries?pipeline_id=&group_by=stage|owner&<list filters>
#   => { payload: { group_by:, groups: [{ key, label, count, sum_value_cents, currency }] } }
class Api::V1::Accounts::Crm::Cards::SummariesController < Api::V1::Accounts::Crm::BaseController
  def index
    authorize ::Crm::Card
    summary = ::Crm::Cards::GroupSummary.new(
      scope: policy_scope(::Crm::Card),
      params: params,
      group_by: params[:group_by],
      conversation_visibility: ::Crm::Conversations::Visibility.new(account: Current.account, user: Current.user, account_user: Current.account_user)
    ).perform
    render json: { payload: summary }
  end
end
