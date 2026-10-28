class Api::V1::Accounts::Instagram::AuthorizationsController < Api::V1::Accounts::OauthAuthorizationController
  include InstagramConcern
  include Instagram::IntegrationHelper

  before_action :ensure_meta_available

  rescue_from Instagram::Testers::Error, with: :render_tester_error

  def create
    if browser_assisted_authorization?
      render json: Instagram::Testers::BrowserAuthorization.new.prepare(
        account_id: Current.account.id, actor_id: current_user.id,
        selection_token: params.permit(:tester_selection_token)[:tester_selection_token],
        authorization_attestation: params.permit(:tester_authorization_attestation)[:tester_authorization_attestation],
        return_to: params.permit(:return_to)[:return_to]
      ), status: :ok
      return
    end

    oauth_state = authorization_state
    raise Instagram::Testers::Error, 'meta_unavailable' if oauth_state.blank?

    # https://developers.facebook.com/docs/instagram-platform/instagram-api-with-instagram-login/business-login#step-1--get-authorization
    redirect_url = instagram_authorization_url(oauth_state, extra_scopes: reauth_purpose&.dig(:scopes) || [])
    if redirect_url
      render json: { success: true, url: redirect_url }
    else
      render json: { success: false }, status: :unprocessable_entity
    end
  end

  private

  # Connecting a new account creates an inbox (inbox_manage); reauthorizing a live inbox swaps its credentials
  # (integration_manage). Admin always (#2027).
  def check_authorization
    check_permission_granted!(params.key?(:inbox_id) ? 'integration_manage' : 'inbox_manage')
  end

  def browser_assisted_authorization?
    Instagram::Testers::BrowserOperationStore.runtime_enabled? &&
      Current.account.feature_enabled?('instagram_assisted_onboarding') &&
      !params.key?(:inbox_id) && params[:return_to] != 'inbox'
  end

  def ensure_meta_available
    raise Instagram::Testers::Error, 'forbidden' unless Current.account.feature_enabled?('channel_instagram')
    raise Instagram::Testers::Error, 'forbidden' if ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('DISABLE_META_INBOX_CREATION'))
  end

  def authorization_state
    inbox = reauthorization_inbox if params.key?(:inbox_id) || reauthorization_return_to?
    selection = tester_selection if inbox.nil? && Current.account.feature_enabled?('instagram_assisted_onboarding')
    generate_instagram_token(Current.account.id, params.permit(:return_to)[:return_to],
                             actor_id: current_user.id, tester_selection: selection, inbox: inbox,
                             purpose: (params[:purpose] if reauth_purpose), ad_id: reauth_ad_id)
  end

  # O anúncio para onde a pessoa volta (#2196): só num purpose que volta a um anúncio (`ad: true`) e só de dígitos,
  # porque vira parte do endereço de volta.
  def reauth_ad_id
    ad_id = params[:ad_id]
    return if ad_id.nil?
    raise Instagram::Testers::Error, 'invalid_selection' unless reauth_purpose&.dig(:ad) && Instagram::Testers::OauthBinding.ad_id?(ad_id)

    ad_id
  end

  def reauthorization_inbox
    inbox_id = params[:inbox_id]
    valid = inbox_id.is_a?(Integer) && inbox_id.positive? && reauthorization_return_to? && !params.key?(:tester_selection_token)
    raise Instagram::Testers::Error, 'invalid_selection' unless valid

    inbox = Current.account.inboxes.find_by(id: inbox_id, channel_type: 'Channel::Instagram')
    raise Instagram::Testers::Error, 'invalid_selection' unless inbox

    inbox
  end

  # Reautorizar a caixa: pela própria caixa ('inbox') ou por Anúncios da Meta ('meta_ads') com um `purpose` da lista
  # REAUTH_PURPOSES cuja flag está ligada na conta.
  def reauthorization_return_to?
    params[:return_to] == 'inbox' || reauth_purpose.present?
  end

  def reauth_purpose
    return unless params[:return_to] == 'meta_ads'

    purpose = REAUTH_PURPOSES[params[:purpose]]
    purpose if purpose && Current.account.feature_enabled?(purpose[:flag])
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
