module Instagram::IntegrationHelper
  REQUIRED_SCOPES = %w[instagram_business_basic instagram_business_manage_messages].freeze
  # Reautorização que sai de Anúncios da Meta (return_to 'meta_ads') pedindo um escopo a mais, até a Meta aprovar o
  # escopo e ele entrar em REQUIRED_SCOPES. O servidor decide o escopo pelo `purpose`, nunca o front; só com a flag
  # dele ligada. `return_query` é a aba para onde a pessoa volta e `return_path` a tela, quando não é Anúncios da Meta
  # (lista fixa: nunca endereço livre).
  # Contrato comum com o #2196 (comentários dos anúncios no Instagram), que soma a entrada dele.
  # - meta_ads_organico (#2199): Seus posts.
  # - seus_posts (#2304): a página própria Seus posts, em Crescer.
  # - seus_posts_comentarios (#2305): a mesma página com os comentários de cada post; pede os números e os
  #   comentários juntos, para a nova autorização não perder os números.
  # - meta_ads_comentarios_instagram (#2196): comentários do anúncio, na aba Resultado; volta ao anúncio (`ad_id`, só
  #   em purpose com `ad: true`).
  REAUTH_PURPOSES = {
    'meta_ads_organico' => { flag: 'meta_ads_organico', scopes: %w[instagram_business_manage_insights], return_query: 'aba=organico' },
    'seus_posts' => { flag: 'seus_posts', scopes: %w[instagram_business_manage_insights], return_path: 'seus-posts' },
    'seus_posts_comentarios' => { flag: 'seus_posts_comentarios',
                                  scopes: %w[instagram_business_manage_insights instagram_business_manage_comments],
                                  return_path: 'seus-posts' },
    'meta_ads_comentarios_instagram' => { flag: 'meta_ads_comentarios_instagram', scopes: %w[instagram_business_manage_comments],
                                          return_query: 'aba=resultado', ad: true }
  }.freeze

  # Generates a signed JWT token for Instagram integration
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @param actor_id [Integer] The user who is authorized to manage account inboxes
  # @param return_to [String, nil] Optional onboarding return hint
  # @param reauth [Hash] inbox: a caixa que se reautoriza; purpose: a entrada de REAUTH_PURPOSES (#2199/#2196);
  #   ad_id: o anúncio para onde a pessoa volta (#2196, só dígitos, conferido por quem chama)
  # @return [String, nil] The bound JWT token or nil if signing/configuration fails
  def generate_instagram_token(account_id, return_to = nil, actor_id:, tester_selection: nil, **reauth)
    return if client_secret.blank?

    payload = token_payload(account_id, return_to, actor_id: actor_id, tester_selection: tester_selection, **reauth)
    JWT.encode(payload, client_secret, 'HS256')
  rescue StandardError
    Rails.logger.error('Instagram token generation failed')
    nil
  end

  def token_payload(account_id, return_to = nil, actor_id:, tester_selection: nil, **reauth)
    payload = { sub: account_id, actor_id: actor_id, state_version: Instagram::Testers::OauthBinding::STATE_VERSION,
                installation: Instagram::Testers::OauthBinding.installation, iat: Time.current.to_i,
                exp: (Time.current + Instagram::Testers::OauthBinding::TTL).to_i, jti: SecureRandom.uuid }
    payload[:return_to] = return_to if return_to.present?
    payload[:tester_selection] = tester_selection if tester_selection
    reauth_payload(payload, **reauth)
  end

  def reauth_payload(payload, inbox: nil, purpose: nil, ad_id: nil)
    payload[:purpose] = purpose if purpose
    payload[:ad_id] = ad_id if ad_id
    if inbox
      payload[:inbox_id] = inbox.id
      payload[:instagram_id] = inbox.channel.instagram_id
    end
    payload
  end

  def instagram_authorization_url(oauth_state, extra_scopes: [])
    instagram_client.auth_code.authorize_url(
      {
        redirect_uri: "#{base_url}/instagram/callback",
        scope: (REQUIRED_SCOPES + extra_scopes).join(','),
        enable_fb_login: '0',
        force_reauth: 'true',
        response_type: 'code',
        state: oauth_state
      }
    )
  end

  # Verifies and decodes a Instagram JWT token
  #
  # @param token [String] The JWT token to verify
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_instagram_token(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)&.dig('sub')
  end

  # Reads the onboarding return hint from a Instagram JWT token, if present.
  def instagram_token_return_to(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)&.dig('return_to')
  end

  def instagram_token_payload(token)
    return if token.blank? || client_secret.blank?

    decode_token(token, client_secret)
  end

  private

  def client_secret
    @client_secret ||= GlobalConfigService.load('INSTAGRAM_APP_SECRET', nil)
  end

  def decode_token(token, secret)
    payload = JWT.decode(token, secret, true, algorithm: 'HS256', verify_expiration: true).first
    Instagram::Testers::OauthBinding.validate_payload!(payload)
    payload
  rescue StandardError
    Rails.logger.error('Instagram token verification failed')
    nil
  end
end
