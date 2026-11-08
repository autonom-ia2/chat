class Api::V1::Accounts::Crm::GoogleConversionFeedsController < Api::V1::Accounts::Crm::BaseController
  def create
    # The feed token is issued by the platform and opens a public URL (#2027): admin or token_manage.
    check_permission_granted!('token_manage')

    token = Crm::GoogleOffline::FeedToken.fetch_or_create!(Current.account)
    render json: {
      token: token,
      url: "#{request.base_url}/google_conversions/#{token}.csv"
    }, status: :created
  end
end
