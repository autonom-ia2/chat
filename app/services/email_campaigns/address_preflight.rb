class EmailCampaigns::AddressPreflight
  # Exact curated variants only; never fuzzy-block arbitrary business domains.
  PROVIDER_TYPOS = { 'gmial.com' => 'gmail.com', 'gmail.con' => 'gmail.com', 'hotmial.com' => 'hotmail.com' }.freeze

  def initialize(validator: nil)
    @validator = validator
  end

  def call(email)
    local, domain = email.to_s.strip.split('@', 2)
    return outcome('invalid', 'invalid_email') if domain.nil? || local.empty?
    return outcome('invalid', 'unsupported_local_part') unless local.ascii_only?
    # Keep recipient identity unchanged. Unicode domains need an explicitly reviewed
    # ASCII/Punycode import; already encoded xn-- domains use ordinary DNS validation.
    return outcome('review', 'idn_requires_ascii_domain') unless domain.ascii_only?

    domain = domain.downcase
    suggestion = PROVIDER_TYPOS[domain]
    return outcome('review', 'provider_typo').merge(suggestion: "#{local}@#{suggestion}") if suggestion
    return outcome('unknown', 'dns_disabled') unless @validator

    @validator.call(domain)
  end

  private

  def outcome(status, reason)
    { status: status, reason_code: reason, valid_until: nil }
  end
end
