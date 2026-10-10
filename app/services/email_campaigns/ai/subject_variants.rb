# Alternative subjects of an AI e-mail (#1076). The prompt asks for exactly 3; the JSON schema does not
# enforce it (strict-schema support for minItems/maxItems is not verified with the provider), so this
# keeps the first 3 non-empty unique variants. Fewer than 3 are accepted with a warning — the
# generation never fails because of it.
class EmailCampaigns::Ai::SubjectVariants
  WANTED = 3

  attr_reader :variants

  def initialize(raw)
    texts = raw.is_a?(Array) ? raw.map { |value| value.to_s.strip } : []
    @variants = texts.reject(&:empty?).uniq.first(WANTED)
  end

  def warning
    return if variants.size >= WANTED

    { 'check' => 'subject_variants', 'detail' => "#{variants.size} of #{WANTED}" }
  end
end
