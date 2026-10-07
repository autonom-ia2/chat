class Instagram::Testers::BrowserAuthorization
  include InstagramConcern
  include Instagram::IntegrationHelper

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
end
