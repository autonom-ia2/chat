class Instagram::UserDetailsService
  class Error < CustomExceptions::InstagramApiError; end

  pattr_initialize [:access_token!]

  def perform
    response = HTTParty.get(
      "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}/me",
      query: {
        fields: 'id,username,user_id,name,profile_picture_url,account_type',
        access_token: access_token
      },
      headers: { 'Accept' => 'application/json' }
    )

    raise Error.new('instagram_user_details_failed', response.code), cause: nil unless response.success?

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise Error.new('instagram_invalid_response', 502), cause: nil
  end
end
