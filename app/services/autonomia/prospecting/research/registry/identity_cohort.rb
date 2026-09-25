# Coorte de identidade (porte de identity-hydration-cohort.ts do Orth, #679). Recebe até 3 CNPJs candidatos da
# descoberta, busca cada um no cadastro público e só então chama o matcher, uma vez, com a coorte inteira. Se algum
# cadastro falhar, o matcher nem roda: decidir entre candidatos com um deles faltando é chutar.
#
# Só a empresa aceita sai daqui. As outras não são guardadas em lugar nenhum (no Orth havia um "descarte por
# referência" do snapshot; aqui nada foi gravado, então basta não devolver).
#
#   candidates: [{ cnpj:, skip_hydration: }] — skip_hydration marca o candidato que a descoberta já recusou (inativo);
#               o matcher o recebe com cadastro nil e não pode aceitá-lo.
#   matcher:    callable(companies) -> { decision:, accepted_cnpj:, ... }, com companies = { cnpj => Company ou nil }.
class Autonomia::Prospecting::Research::Registry::IdentityCohort
  Registry = Autonomia::Prospecting::Research::Registry

  DECISIONS = %w[accept not_found ambiguous rejected not_run].freeze
  SCORE_FIELDS = %i[top_score second_score name_similarity].freeze
  CNPJ_LENGTH = 14

  Result = Data.define(:status, :reason, :match, :accepted)

  def initialize(hydrator: Registry::Hydrator.new)
    @hydrator = hydrator
  end

  def run(candidates:, matcher:)
    parsed = parse_candidates(candidates)
    return parsed if parsed.is_a?(Result)

    companies = hydrate(parsed)
    return companies if companies.is_a?(Result)

    decide(matcher, parsed.to_h { |candidate| [candidate[:cnpj], companies[candidate[:cnpj]]] })
  end

  private

  def parse_candidates(candidates)
    return provider_error('invalid_discovery_cohort') unless candidates.is_a?(Array) && candidates.size <= Registry::Hydrator::MAX_CANDIDATES

    parsed = candidates.map { |candidate| parse_candidate(candidate) }
    return provider_error('invalid_discovery_candidate') unless parsed.all?
    return provider_error('invalid_discovery_cohort') unless parsed.uniq { |candidate| candidate[:cnpj] }.size == parsed.size

    parsed
  end

  def parse_candidate(candidate)
    return nil unless candidate.is_a?(Hash) && candidate[:cnpj].is_a?(String)

    cnpj = Autonomia::Prospecting::Research::Normalization.digits(candidate[:cnpj])
    cnpj.length == CNPJ_LENGTH ? { cnpj: cnpj, skip: candidate[:skip_hydration] == true } : nil
  end

  def hydrate(parsed)
    required = parsed.reject { |candidate| candidate[:skip] }.pluck(:cnpj)
    return {} if required.empty?

    hydrations = @hydrator.hydrate(required)
    error = hydration_error(hydrations, required)
    return provider_error(error) if error

    hydrations.to_h { |item| [item.cnpj, item.company] }
  end

  def hydration_error(hydrations, required)
    return 'invalid_hydration_response' unless hydrations.map(&:cnpj) == required
    return 'invalid_hydration_snapshot' if hydrations.any? { |item| other_company?(item) }

    'hydration_incomplete' unless hydrations.all?(&:company)
  end

  def other_company?(hydration) = hydration.company.present? && hydration.company.cnpj != hydration.cnpj

  def decide(matcher, companies)
    match = validated_match(call_matcher(matcher, companies), companies)
    return match if match.is_a?(Result)

    accepted = match[:decision] == 'accept' ? companies.fetch(match[:accepted_cnpj]) : nil
    Result.new(status: :complete, reason: nil, match: match, accepted: accepted)
  end

  def call_matcher(matcher, companies)
    matcher.call(companies.dup.freeze)
  rescue StandardError
    provider_error('matcher_failed')
  end

  def validated_match(raw, companies)
    return raw if raw.is_a?(Result)
    return provider_error('invalid_matcher_result') unless raw.is_a?(Hash)

    match = raw.to_h { |key, value| [key.to_sym, value.frozen? ? value : value.dup.freeze] }.freeze
    valid_match?(match, companies) ? match : provider_error('invalid_matcher_result')
  end

  def valid_match?(match, companies)
    return false unless DECISIONS.include?(match[:decision]) && match.key?(:accepted_cnpj)
    return false unless SCORE_FIELDS.all? { |field| match[field].nil? || unit_interval?(match[field]) }
    return match[:accepted_cnpj].nil? unless match[:decision] == 'accept'

    companies[match[:accepted_cnpj]].present?
  end

  def unit_interval?(value)
    value.is_a?(Numeric) && value.to_f.finite? && value >= 0 && value <= 1
  end

  def provider_error(reason)
    Result.new(status: :provider_error, reason: reason, match: nil, accepted: nil)
  end
end
