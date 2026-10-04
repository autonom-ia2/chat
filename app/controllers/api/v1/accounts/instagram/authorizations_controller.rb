class Api::V1::Accounts::Instagram::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  before_action :ensure_meta_available

  rescue_from Instagram::Testers::Error, with: :render_tester_error

  def create
    oauth_state = authorization_state
    raise Instagram::Testers::Error, 'meta_unavailable' if oauth_state.blank?

    # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#step-1--get-authorization
    redirect_url = instagram_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/instagram/callback",
        scope: REQUIRED_SCOPES.join(','),
        enable_fb_login: '0',
        force_reauth: 'true',
        response_type: 'code',
        state: oauth_state
      }
    )
    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  def ensure_meta_available
    raise Instagram::Testers::Error, 'forbidden' unless Current.account.feature_enabled?('channel_instagram')
    raise Instagram::Testers::Error, 'forbidden' if ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('DISABLE_META_INBOX_CREATION'))
  end

  def authorization_state
    inbox = reauthorization_inbox if params.key?(:inbox_id) || params[:return_to] == 'inbox'
    selection = tester_selection if inbox.nil? && Current.account.feature_enabled?('instagram_assisted_onboarding')
    generate_instagram_token(Current.account.id, params.permit(:return_to)[:return_to],
                             actor_id: current_user.id, tester_selection: selection, inbox: inbox)
  end

  def reauthorization_inbox
    inbox_id = params[:inbox_id]
    valid = inbox_id.is_a?(Integer) && inbox_id.positive? && params[:return_to] == 'inbox' && !params.key?(:tester_selection_token)
    raise Instagram::Testers::Error, 'invalid_selection' unless valid

    inbox = Current.account.inboxes.find_by(id: inbox_id, channel_type: 'Channel::Instagram')
    raise Instagram::Testers::Error, 'invalid_selection' unless inbox

    inbox
  end

  def tester_selection
    raise Instagram::Testers::Error, 'forbidden' unless current_user

    token = params.permit(:tester_selection_token)[:tester_selection_token]
    raise Instagram::Testers::Error, 'invalid_selection' unless token.is_a?(String) && token.bytesize.between?(1, 4096)

    Instagram::Testers::OauthBinding.prepare(token: token, account_id: Current.account.id, actor_id: current_user.id)
  end

  def render_tester_error(error)
    render json: { error_code: error.code }, status: error.http_status
  end
end
