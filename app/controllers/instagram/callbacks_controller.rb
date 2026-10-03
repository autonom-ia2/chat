class Instagram::CallbacksController < ApplicationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  def show
    # Check if Instagram redirected with an error (user canceled authorization)
    # See: https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#canceled-authorization
    if params[:error].present?
      @tester_flow = instagram_token_payload(params[:state])&.key?('tester_selection')
      handle_authorization_error
      return
    end

    process_successful_authorization
  rescue CustomExceptions::Inbox::LimitExceeded => e
    handle_limit_error(e)
  rescue StandardError => e
    handle_error(e)
  end

  private

  # Process the authorization code and create inbox
  def process_successful_authorization
    return redirect_to '/app' unless account_id

    prepare_tester_callback

    @response = instagram_client.auth_code.get_token(
      oauth_code,
      redirect_uri: "#{base_url}/#{provider_name}/callback",
      grant_type: 'authorization_code'
    )

    @long_lived_token_response = exchange_for_long_lived_token(@response.token)
    inbox, already_exists = find_or_create_inbox

    return redirect_to app_onboarding_inbox_setup_url(account_id: account_id) if return_to == 'onboarding'

    if already_exists
      redirect_to app_instagram_inbox_settings_url(account_id: account_id, inbox_id: inbox.id)
    else
      redirect_to app_instagram_inbox_agents_url(account_id: account_id, inbox_id: inbox.id)
    end
  end

  def prepare_tester_callback
    payload = instagram_token_payload(params[:state])
    @tester_flow = payload&.key?('tester_selection')
    return unless @tester_flow

    Instagram::Testers::OauthBinding.claim!(payload)
    @tester_selection = payload.fetch('tester_selection')
  end

  # Handle all errors that might occur during authorization
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#sample-rejected-response
  def handle_error(error)
    if @tester_flow || error.is_a?(Instagram::Testers::Error)
      code = error.is_a?(Instagram::Testers::Error) ? error.code : 'meta_unavailable'
      return redirect_to_error_page('error_type' => code, 'code' => 422, 'error_message' => code)
    end

    error_info = extract_error_info(error)
    safe_error = CustomExceptions::InstagramApiError.new(error_info['error_message'], error_info['code'])
    Rails.logger.error("Instagram Channel creation Error: #{safe_error.code}")
    ChatwootExceptionTracker.new(safe_error).capture_exception
    redirect_to_error_page(error_info)
  end

  def handle_limit_error(error)
    redirect_to_error_page(
      'error_type' => error.class.name,
      'code' => Rack::Utils.status_code(error.http_status),
      'error_message' => error.message
    )
  end

  # Extract error details from the exception
  def extract_error_info(error)
    if error.is_a?(OAuth2::Error)
      { 'error_type' => 'OAuthException', 'code' => 400, 'error_message' => 'instagram_authorization_failed' }
    else
      { 'error_type' => 'InstagramApiError', 'code' => 500, 'error_message' => 'instagram_connection_failed' }
    end
  end

  # Handles the case when a user denies permissions or cancels the authorization flow
  # Error parameters are documented at:
  # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#canceled-authorization
  def handle_authorization_error
    error_info = {
      'error_type' => 'authorization_error',
      'code' => 400,
      'error_message' => 'Authorization was denied'
    }

    Rails.logger.error("Instagram Authorization Error: #{error_info['error_message']}")
    redirect_to_error_page(error_info)
  end

  # Centralized method to redirect to error page with appropriate parameters
  # This ensures consistent error handling across different error scenarios
  # Frontend will handle the error page based on the error_type
  def redirect_to_error_page(error_info)
    redirect_to app_new_instagram_inbox_url(
      account_id: account_id,
      error_type: error_info['error_type'],
      code: error_info['code'],
      error_message: error_info['error_message']
    )
  end

  def find_or_create_inbox
    user_details = fetch_instagram_user_details(@long_lived_token_response['access_token'])
    if @tester_selection && Instagram::Testers::Validation.normalize_username(user_details['username']) != @tester_selection.fetch('username')
      raise Instagram::Testers::Error, 'invalid_selection'
    end

    channel_instagram = find_channel_by_instagram_id(user_details['user_id'].to_s)
    channel_exists = channel_instagram.present?

    if channel_instagram
      update_channel(channel_instagram, user_details)
    else
      channel_instagram = create_channel_with_inbox(user_details)
    end

    # reauthorize channel, this code path only triggers when instagram auth is successful
    # reauthorized will also update cache keys for the associated inbox
    channel_instagram.reauthorized!

    [channel_instagram.inbox, channel_exists]
  end

  def find_channel_by_instagram_id(instagram_id)
    Channel::Instagram.find_by(instagram_id: instagram_id, account: account)
  end

  def update_channel(channel_instagram, user_details)
    expires_at = Time.current + @long_lived_token_response['expires_in'].seconds

    channel_instagram.update!(
      access_token: @long_lived_token_response['access_token'],
      expires_at: expires_at,
      provider_name: user_details['username'],
      app_scoped_user_id: user_details['id'].to_s
    )

    channel_instagram
  end

  def create_channel_with_inbox(user_details)
    ActiveRecord::Base.transaction do
      expires_at = Time.current + @long_lived_token_response['expires_in'].seconds

      channel_instagram = Channel::Instagram.create!(
        access_token: @long_lived_token_response['access_token'],
        instagram_id: user_details['user_id'].to_s,
        app_scoped_user_id: user_details['id'].to_s,
        account: account,
        expires_at: expires_at,
        provider_name: user_details['username']
      )

      account.inboxes.create!(
        account: account,
        channel: channel_instagram,
        name: user_details['username']
      )

      channel_instagram
    end
  end

  def account_id
    return unless params[:state]

    verify_instagram_token(params[:state])
  end

  def return_to
    instagram_token_return_to(params[:state])
  end

  def oauth_code
    params[:code]
  end

  def account
    @account ||= Account.find(account_id)
  end

  def provider_name
    'instagram'
  end
end
