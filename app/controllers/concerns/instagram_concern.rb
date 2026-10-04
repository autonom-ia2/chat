module InstagramConcern
  extend ActiveSupport::Concern

  def instagram_client
    ::OAuth2::Client.new(
      client_id,
      client_secret,
      {
        site: 'https://api.instagram.com',
        authorize_url: 'https://www.instagram.com/oauth/authorize',
        token_url: 'https://api.instagram.com/oauth/access_token',
        auth_scheme: :request_body,
        token_method: :post
      }
    )
  end

  private

  def client_id
    GlobalConfigService.load('INSTAGRAM_APP_ID', nil)
  end

  def client_secret
    GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def exchange_for_long_lived_token(short_lived_token)
    endpoint = 'https://graph.instagram.com/access_token'
    params = {
      grant_type: 'ig_exchange_token',
      client_secret: client_secret,
      access_token: short_lived_token,
      client_id: client_id
    }

    make_api_request(endpoint, params, 'instagram_token_exchange_failed')
  end

  def fetch_instagram_user_details(access_token)
    Instagram::UserDetailsService.new(access_token: access_token).perform
  end

  def make_api_request(endpoint, params, error_code)
    response = HTTParty.get(
      endpoint,
      query: params,
      headers: { 'Accept' => 'application/json' }
    )

    raise CustomExceptions::InstagramApiError.new(error_code, response.code), cause: nil unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise CustomExceptions::InstagramApiError.new('instagram_invalid_response', 502), cause: nil
  end

  def base_url
    ENV.fetch('FRONTEND_URL', 'http://localhost:3000')
  end
end
