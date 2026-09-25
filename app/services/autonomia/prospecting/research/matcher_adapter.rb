# Junta o candidato da BigDataCorp com a identidade do cadastro público e monta a entrada do matcher (porte de
# bigdatacorp-matcher-adapter.ts do Orth, #679).
#
# Nome, cidade, UF e situação saem do cadastro, nunca da BigDataCorp: a UF da BigDataCorp é a da matriz. A nota de nome
# é a maior porcentagem válida da BigDataCorp (razão social vence o empate). Os telefones do cadastro entram (além do
# Orth, que não os lê, decisão do Rodrigo de 25/09) e qualquer um deles igual ao do Google vale como sinal forte; o domínio
# só entra quando o CNPJ do site do lead é o mesmo do candidato. Antes do cadastro, dois casos já rejeitam e nem
# consultam: CNPJ do site diferente (conflito) e situação BAIXADA na BigDataCorp.
module Autonomia::Prospecting::Research::MatcherAdapter
  MAX_IDENTITY_CANDIDATES = 3
  CLOSED_STATUSES = %w[BAIXADA INATIVA].freeze
  INACTIVE = 'INATIVA'.freeze
  Cnpj = Autonomia::Prospecting::Research::Cnpj
  Matcher = Autonomia::Prospecting::Research::IdentityMatcher

  # Identidade do cadastro público que o matcher usa. `cnpj` é o CNPJ que o cadastro devolveu.
  Identity = Struct.new(:cnpj, :legal_name, :trade_name, :status, :city, :uf, :domain, :phones, keyword_init: true)
  Adaptation = Struct.new(:kind, :cnpj, :candidate, :reason, :audit, keyword_init: true)

  module_function

  def normalize_status(status)
    normalized = status.to_s.strip.upcase
    return if normalized.empty?

    CLOSED_STATUSES.include?(normalized) ? INACTIVE : normalized
  end

  # CNPJ com dígito válido e ao menos um nome. Candidato inválido derruba a coorte inteira, como no Orth.
  def valid_candidate?(candidate)
    Cnpj.valid?(candidate.cnpj) && [candidate.name, candidate.trade_name].any? { |name| name.to_s.strip.present? }
  end

  def pre_hydration_hard_reject(candidate, site_cnpj: nil)
    return unless valid_candidate?(candidate)
    return { cnpj: candidate.cnpj, reason: 'cnpj_conflict' } if site_cnpj.present? && Cnpj.valid?(site_cnpj) && site_cnpj != candidate.cnpj
    return { cnpj: candidate.cnpj, reason: 'company_inactive' } if candidate.status.to_s.strip.upcase == 'BAIXADA'

    nil
  end

  def pre_hydration_matcher_candidate(candidate, site_cnpj: nil)
    reject = pre_hydration_hard_reject(candidate, site_cnpj: site_cnpj)
    raise ArgumentError, 'candidate is not eligible for a pre-hydration hard reject' unless reject

    score = (valid_percentages(candidate).max || 0) / 100.0
    Matcher::Candidate.new(
      cnpj: candidate.cnpj, name: [candidate.name, candidate.trade_name].find(&:present?).to_s.strip,
      cnpj_conflict_with: reject[:reason] == 'cnpj_conflict' ? site_cnpj : nil,
      status: reject[:reason] == 'company_inactive' ? INACTIVE : nil, match_score: score, name_similarity: score
    )
  end

  def adapt(candidate, identity)
    return invalid(candidate, 'snapshot_cnpj_mismatch') unless identity.respond_to?(:cnpj) && identity.cnpj == candidate.cnpj
    return invalid(candidate, 'snapshot_identity_invalid') unless valid_identity?(identity)

    source, percentage = selected_name(candidate)
    return matcher_candidate(candidate, identity, source, percentage) if source

    Adaptation.new(kind: :non_qualifiable, cnpj: candidate.cnpj, reason: 'invalid_name_similarity_percentage', audit: audit(candidate, nil))
  end

  # A maior porcentagem válida decide qual nome do cadastro o matcher compara; a razão social vence o empate.
  def selected_name(candidate)
    official = valid_percentage(candidate.official_name_percentage)
    trade = valid_percentage(candidate.trade_name_percentage)
    return [:official, official] if official && (trade.nil? || official >= trade)

    trade ? [:trade, trade] : nil
  end

  def matcher_candidate(candidate, identity, source, percentage)
    name = (source == :official ? identity.legal_name : identity.trade_name).to_s.strip
    return invalid(candidate, 'snapshot_identity_invalid') if name.empty?

    score = percentage / 100.0
    Adaptation.new(
      kind: :matcher_candidate, cnpj: candidate.cnpj, audit: audit(candidate, source),
      candidate: Matcher::Candidate.new(
        cnpj: candidate.cnpj, name: name, city: identity.city.strip, uf: identity.uf.strip, phone: Array(identity.phones).presence,
        domain: identity.domain.presence, status: normalize_status(identity.status), match_score: score, name_similarity: score
      )
    )
  end

  def valid_identity?(identity)
    identity.legal_name.to_s.strip.present? && identity.status.to_s.strip.present? && identity.city.to_s.strip.present? &&
      Autonomia::Prospecting::Research::Normalization.uf(identity.uf).present?
  end

  def valid_percentages(candidate)
    [candidate.official_name_percentage, candidate.trade_name_percentage].filter_map { |value| valid_percentage(value) }
  end

  def valid_percentage(value)
    value.is_a?(Numeric) && value.finite? && value.between?(0, 100) ? value : nil
  end

  def audit(candidate, source)
    { selected_name_source: source, is_headquarter: candidate.is_headquarter, headquarter_state: candidate.headquarter_state,
      match_keys: Array(candidate.match_keys).dup, provider_index: candidate.provider_index }
  end

  def invalid(candidate, reason)
    Adaptation.new(kind: :invalid_snapshot, cnpj: candidate.cnpj, reason: reason)
  end
end
