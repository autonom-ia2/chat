class Instagram::Testers::BrowserAuthorization
  include InstagramConcern
  include Instagram::IntegrationHelper

  # Consumes a fresh accepted-role proof before constructing a new OAuth state.
  # The proof is single-use and remains independent from the callback nonce.
  def prepare(account_id:, actor_id:, selection_token:, authorization_attestation:, return_to: nil)
    validate_return_to!(return_to)
    configuration = Instagram::Testers::Configuration.new(account_id: account_id)
    configuration.ensure_available!
    Instagram::Testers::RateLimiter.check!(account_id: account_id, actor_id: actor_id)
    selected = Instagram::Testers::Selection.new(account_id: account_id, actor_id: actor_id, app_id: configuration.app_id)
                                            .verify(selection_token)
    Instagram::Testers::AuthorizationAttestation.consume!(token: authorization_attestation, selection: selected)

    perform(account_id: account_id, actor_id: actor_id, selected: selected, return_to: return_to)
  end

  # Called only after the browser operation has validated a fresh accepted role.
  # The OAuth callback remains responsible for consuming the state nonce.
  def perform(account_id:, actor_id:, selected:, return_to:)
    configuration = Instagram::Testers::Configuration.new(account_id: account_id)
    configuration.ensure_available!
    raise Instagram::Testers::Error, 'invalid_selection' unless configuration.app_id == selected.fetch('app_id')
    raise Instagram::Testers::Error, 'forbidden' if ActiveModel::Type::Boolean.new.cast(GlobalConfig.get_value('DISABLE_META_INBOX_CREATION'))

    oauth_state = generate_instagram_token(account_id, return_to, actor_id: actor_id, tester_selection: selected)
    payload = instagram_token_payload(oauth_state)
    raise Instagram::Testers::Error, 'meta_unavailable' unless payload

    Instagram::Testers::OauthBinding.authorize!(payload)
    url = instagram_authorization_url(oauth_state)
    raise Instagram::Testers::Error, 'meta_unavailable' unless url

    { success: true, url: url }
  end

  private

  def validate_return_to!(return_to)
    valid = return_to.nil? || (return_to.is_a?(String) && return_to.bytesize <= 64 && !return_to.match?(/[\0-\x1f\x7f]/))
    raise Instagram::Testers::Error, 'invalid_selection' unless valid
  end
end
