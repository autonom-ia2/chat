class Instagram::Testers::Selection
  TTL = 2.hours
  PURPOSE = 'instagram_tester_selection'.freeze

  def initialize(account_id:, actor_id:, app_id:)
    @scope = { 'account_id' => account_id.to_s, 'actor_id' => actor_id.to_s, 'app_id' => app_id,
               'installation' => Instagram::Testers::OauthBinding.installation }
  end

  def issue(candidate)
    verifier.generate(@scope.merge('id' => candidate.fetch(:id), 'username' => candidate.fetch(:username)), expires_in: TTL, purpose: PURPOSE)
  end

  def verify(token)
    raise Instagram::Testers::Error, 'invalid_selection' unless token.is_a?(String) && token.bytesize.between?(1, 4096)

    data = verifier.verified(token, purpose: PURPOSE)
    valid = data.is_a?(Hash) && @scope.all? { |key, value| data[key] == value } &&
            Instagram::Testers::Validation.target?(data)
    raise Instagram::Testers::Error, 'invalid_selection' unless valid

    data
  end

  private

  def verifier
    Rails.application.message_verifier(PURPOSE)
  end
end
