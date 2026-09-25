# Decide qual candidato é a empresa do lead (porte de company-identity-matcher.ts do Orth, #679).
#
# Rejeição dura: conflito com o CNPJ do site, empresa INATIVA, matriz no lugar de unidade, domínio oficial diferente,
# UF diferente. Qualifica quem casa cidade e UF e tem semelhança de nome de 0,80, ou 0,65 quando telefone ou domínio
# batem. Entre os qualificados vence a maior nota, com a ordem do fornecedor como desempate; diferença menor que 0,10
# entre os dois primeiros é ambígua.
module Autonomia::Prospecting::Research::IdentityMatcher
  PRIMARY_SIMILARITY = 0.65
  DEFAULT_SIMILARITY = 0.8
  AMBIGUITY_MARGIN = 0.1
  INACTIVE = 'INATIVA'.freeze
  HEADQUARTERS_SCOPE = 'headquarters'.freeze
  Normalization = Autonomia::Prospecting::Research::Normalization

  Place = Struct.new(:name, :city, :uf, :phone, :website, keyword_init: true)
  Candidate = Struct.new(:cnpj, :name, :city, :uf, :phone, :domain, :cnpj_conflict_with, :status, :franchise_scope,
                         :match_score, :name_similarity, keyword_init: true)
  Match = Struct.new(:decision, :accepted_cnpj, :reason, :top_score, :second_score, :name_similarity, keyword_init: true)

  module_function

  # Telefone igual ao do lead em mais de um candidato não identifica nenhum: é o telefone de quem cadastra os outros
  # (escritório de contabilidade no CNPJ dos clientes, central, dono com dois CNPJs). Aí o telefone deixa de ser sinal
  # forte para todos e vale só o nome, como sem telefone (#679).
  def match(place, candidates)
    entries = qualify_all(place, candidates)
    entries = qualify_all(Place.new(**place.to_h, phone: nil), candidates) if shared_phone?(entries)
    qualified = entries.select { |entry| entry[:qualified] }
                       .sort_by { |entry| [-entry[:candidate].match_score, entry[:index]] }
    return unqualified_result(entries) if qualified.empty?

    top, second = qualified
    decide(place, top, second)
  end

  def decide(place, top, second)
    top_score = top[:candidate].match_score
    second_score = second&.dig(:candidate)&.match_score
    if second_score && ((top_score - second_score) * 1e12).round / 1e12 < AMBIGUITY_MARGIN
      return empty(:ambiguous, 'top_two_difference_lt_010').tap do |result|
        result.top_score = top_score
        result.second_score = second_score
      end
    end

    Match.new(decision: :accept, accepted_cnpj: top[:candidate].cnpj, reason: accept_reason(place, top),
              top_score: top_score, second_score: second_score, name_similarity: top[:candidate].name_similarity)
  end

  def unqualified_result(entries)
    return empty(:rejected, entries.first[:hard_reject]) if entries.any? && entries.all? { |entry| entry[:hard_reject] }

    empty(:not_found, 'no_qualified_candidate')
  end

  # Candidato já rejeitado (CNPJ antigo inativo do mesmo dono) não conta.
  def shared_phone?(entries)
    entries.count { |entry| entry[:phone_exact] && entry[:hard_reject].nil? } > 1
  end

  def qualify_all(place, candidates)
    candidates.each_with_index.map { |candidate, index| qualify(place, candidate, index) }
  end

  def qualify(place, candidate, index)
    found = signals(place, candidate)
    reject = hard_reject(candidate, found)
    primary = found[:phone_exact] || found[:domain_exact]
    threshold = primary ? PRIMARY_SIMILARITY : DEFAULT_SIMILARITY
    qualified = reject.nil? && found[:city_uf_match] && unit_interval?(candidate.match_score) &&
                unit_interval?(candidate.name_similarity) && candidate.name_similarity >= threshold
    found.merge(candidate: candidate, index: index, hard_reject: reject, qualified: qualified)
  end

  def signals(place, candidate)
    place_phone = Normalization.phone(place.phone)
    place_domain = Normalization.registrable_domain(place.website, require_https: true)
    candidate_domain = Normalization.registrable_domain(candidate.domain)
    place_uf = Normalization.uf(place.uf)
    candidate_uf = Normalization.uf(candidate.uf)
    place_city = Normalization.text(place.city)
    {
      phone_exact: place_phone.present? && Array(candidate.phone).any? { |phone| Normalization.phone(phone) == place_phone },
      domain_exact: place_domain.present? && place_domain == candidate_domain,
      city_uf_match: place_city.present? && place_uf.present? && place_city == Normalization.text(candidate.city) && place_uf == candidate_uf,
      place_domain: place_domain, candidate_domain: candidate_domain, place_uf: place_uf, candidate_uf: candidate_uf
    }
  end

  # Na ordem do Orth: a primeira regra que bate é o motivo.
  def hard_reject(candidate, found)
    {
      'cnpj_conflict' => candidate.cnpj_conflict_with.present?,
      'company_inactive' => candidate.status.to_s.strip.upcase == INACTIVE,
      'franchise_headquarters_not_unit' => candidate.franchise_scope == HEADQUARTERS_SCOPE,
      'domain_conflict' => conflicting?(found[:place_domain], found[:candidate_domain]),
      'uf_incompatible' => conflicting?(found[:place_uf], found[:candidate_uf])
    }.find { |_reason, rejected| rejected }&.first
  end

  def conflicting?(place_value, candidate_value)
    place_value.present? && candidate_value.present? && place_value != candidate_value
  end

  def accept_reason(place, entry)
    exact_name = Normalization.business_name(place.name) == Normalization.business_name(entry[:candidate].name)
    return exact_name ? 'exact_name_plus_phone' : 'phone_primary_name_065_plus_city_uf' if entry[:phone_exact]
    return exact_name ? 'exact_name_plus_domain' : 'domain_primary_name_065_plus_city_uf' if entry[:domain_exact]

    exact_name ? 'exact_name_plus_city_uf' : 'name_080_plus_city_uf'
  end

  def unit_interval?(value)
    value.is_a?(Numeric) && value.finite? && value.between?(0, 1)
  end

  def empty(decision, reason)
    Match.new(decision: decision, accepted_cnpj: nil, reason: reason, top_score: nil, second_score: nil, name_similarity: nil)
  end
end
