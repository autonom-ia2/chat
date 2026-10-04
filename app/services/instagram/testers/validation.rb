module Instagram::Testers::Validation
  USERNAME_CHARACTERS = ('a'..'z').to_a.concat(('A'..'Z').to_a).concat(('0'..'9').to_a).push('_', '.').freeze
  DIGITS = ('0'..'9').to_a.freeze

  def self.username?(value)
    value.is_a?(String) && value.length.between?(1, 30) && value.each_char.all? { |char| USERNAME_CHARACTERS.include?(char) }
  end

  def self.normalize_username(value)
    raise Instagram::Testers::Error, 'invalid_username' unless value.is_a?(String)

    username = value.strip.delete_prefix('@').downcase
    raise Instagram::Testers::Error, 'invalid_username' unless username?(username)

    username
  end

  def self.id?(value)
    value.is_a?(String) && value.length.between?(1, 40) && value.each_char.all? { |char| DIGITS.include?(char) }
  end

  def self.target?(value)
    value.is_a?(Hash) && id?(value['id']) && username?(value['username'])
  end

  def self.avatar?(value)
    return true if value.nil?
    return false unless value.is_a?(String) && value.length <= 4096

    uri = URI.parse(value)
    uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    false
  end
end
