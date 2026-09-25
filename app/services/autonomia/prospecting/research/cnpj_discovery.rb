# Descobre o CNPJ do lead (#679, frente A). Não grava nada: devolve um Result para o Runner da frente C.
#
# 1. BigDataCorp basic_data por nome e telefone do lead (até 3 candidatos). Sem credencial: not_configured, sem HTTP.
# 2. O CNPJ que o site do lead mostra corrobora: candidato com outro CNPJ é rejeitado sem ir ao cadastro, e o candidato
#    igual ganha o domínio do site como sinal e SITE_CORROBORATION_BONUS na confiança. O CNPJ do site é lido pela própria
#    pesquisa (Research::SiteCnpj), como no Orth, e nunca vem de enriched_cnpj: um CNPJ aceito antes não corrobora a si
#    mesmo no "verificar novamente".
#    Como no Orth, o CNPJ do site sozinho não vira empresa: sem candidato da BigDataCorp não há empresa.
# 3. Cada candidato restante vai ao cadastro público (hydrator; por padrão Research::Registry.fetch, da frente B) para
#    cidade, UF, razão social, nome fantasia e situação. Cadastro que falha ou vem sem cidade derruba a descoberta.
# 4. O matcher do Orth decide: found, ambiguous ou not_found (sem qualificado ou rejeitado).
#
# A evidência leva só fonte, sinal e número. Nome de empresa ou pessoa não entra.
class Autonomia::Prospecting::Research::CnpjDiscovery
  SITE_CORROBORATION_BONUS = 0.1
  Research = Autonomia::Prospecting::Research
  Adapter = Research::MatcherAdapter
  LOG_TAG = '[Prospecting::Research::CnpjDiscovery]'.freeze

  # status: :found, :not_found, :ambiguous, :not_configured, :failed. company: o objeto que o cadastro devolveu para o CNPJ
  # aceito (para o Runner não consultar de novo), ou nil.
  Result = Struct.new(:status, :cnpj, :confidence, :evidence, :candidates, :error_code, :company, keyword_init: true)

  class Failure < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super
    end
  end

  DEFAULT_HYDRATOR = ->(cnpj) { Autonomia::Prospecting::Research::Registry.fetch(cnpj) }

  DEFAULT_SITE_READER = ->(lead) { Autonomia::Prospecting::Research::SiteCnpj.read(lead) }

  def initialize(lead:, client: nil, hydrator: DEFAULT_HYDRATOR, site_reader: DEFAULT_SITE_READER)
    @lead = lead
    @client = client
    @hydrator = hydrator
    @site_reader = site_reader
    @evidence = []
  end

  def perform
    return result(:not_configured, error_code: 'BIGDATACORP_NOT_CONFIGURED') unless @client || Research::BigDataCorpClient.configured?

    discovered = discover
    return result(:not_found, evidence: [signal('bigdatacorp', 'no_candidates')]) if discovered.empty?

    match_candidates(discovered)
  rescue Research::BigDataCorpClient::Error, Research::BigDataCorpDiscovery::Error, Failure => e
    failed(e.code)
  end

  private

  def discover
    discovery = Research::BigDataCorpDiscovery.new(client: @client || Research::BigDataCorpClient.new)
    candidates = discovery.discover(name: @lead.name, phone: @lead.phone.presence, region: region).candidates
    @candidate_cnpjs = candidates.map(&:cnpj)
    @evidence << signal('bigdatacorp', 'candidates', candidates.size)
    validate_cohort!(candidates)
    candidates
  end

  def validate_cohort!(candidates)
    valid = candidates.size <= Adapter::MAX_IDENTITY_CANDIDATES && candidates.all? { |candidate| Adapter.valid_candidate?(candidate) } &&
            candidates.map(&:cnpj).uniq.size == candidates.size
    raise Failure, 'BIGDATACORP_INVALID_DISCOVERY_COHORT' unless valid
  end

  def match_candidates(candidates)
    rejected, to_hydrate = candidates.partition { |candidate| Adapter.pre_hydration_hard_reject(candidate, site_cnpj: site_cnpj) }
    record_site_signal(candidates)
    hydrated = to_hydrate.to_h { |candidate| [candidate.cnpj, hydrate(candidate)] }
    matcher_candidates = rejected.map { |candidate| Adapter.pre_hydration_matcher_candidate(candidate, site_cnpj: site_cnpj) } +
                         to_hydrate.filter_map { |candidate| adapted(candidate, hydrated[candidate.cnpj][:identity]) }
    match = Research::IdentityMatcher.match(place, matcher_candidates)
    @evidence << signal('matcher', match.reason)
    outcome(match, hydrated)
  end

  def outcome(match, hydrated)
    case match.decision
    when :accept
      found(match, hydrated.fetch(match.accepted_cnpj)[:company])
    when :ambiguous
      result(:ambiguous, confidence: match.top_score.to_f.round(2))
    else
      result(:not_found)
    end
  end

  def found(match, company)
    corroborated = site_cnpj == match.accepted_cnpj
    confidence = [match.top_score + (corroborated ? SITE_CORROBORATION_BONUS : 0), 1.0].min.round(2)
    @evidence << signal('bigdatacorp', 'name_similarity', match.name_similarity.round(2))
    result(:found, cnpj: match.accepted_cnpj, confidence: confidence, company: company)
  end

  def hydrate(candidate)
    company = @hydrator.call(candidate.cnpj)
    raise Failure, 'REGISTRY_HYDRATION_INCOMPLETE' unless company.respond_to?(:legal_name)

    { company: company, identity: identity(company, candidate.cnpj) }
  rescue Failure
    raise
  rescue StandardError => e
    Rails.logger.warn("#{LOG_TAG} registry_failed lead_id=#{@lead.id} error=#{e.class.name}")
    raise Failure, 'REGISTRY_HYDRATION_INCOMPLETE'
  end

  # Contrato da frente B (Research::Registry::Company): registration_state é a UF; a cidade vem em `city`.
  def identity(company, requested_cnpj)
    returned = Research::Cnpj.digits(company.try(:cnpj))
    Adapter::Identity.new(
      cnpj: returned, legal_name: company.legal_name, trade_name: company.try(:trade_name), status: company.try(:registration_status),
      city: company.try(:city), uf: company.try(:registration_state), domain: returned == requested_cnpj && site_cnpj == returned ? site_domain : nil
    )
  end

  def adapted(candidate, identity)
    adaptation = Adapter.adapt(candidate, identity)
    raise Failure, 'REGISTRY_IDENTITY_INVALID' if adaptation.kind == :invalid_snapshot

    adaptation.candidate
  end

  def record_site_signal(candidates)
    return unless site_cnpj

    corroborated = candidates.any? { |candidate| candidate.cnpj == site_cnpj }
    @evidence << signal('official_site', corroborated ? 'cnpj_corroborated' : 'cnpj_conflict')
  end

  def place
    Research::IdentityMatcher::Place.new(name: @lead.name, city: @lead.city, uf: @lead.state, phone: @lead.phone, website: @lead.website)
  end

  def site_cnpj
    return @site_cnpj if defined?(@site_cnpj)

    @site_cnpj = Research::Cnpj.normalize(@site_reader.call(@lead))
  end

  def site_domain
    Research::Normalization.registrable_domain(@lead.website, require_https: true)
  end

  def region
    Autonomia::Prospecting::PhoneContract.region_for(@lead.account)
  end

  def signal(source, name, value = nil)
    { source: source, signal: name, value: value }.compact
  end

  def failed(code)
    Rails.logger.warn("#{LOG_TAG} failed lead_id=#{@lead.id} code=#{code}")
    result(:failed, error_code: code)
  end

  def result(status, evidence: [], **attributes)
    Result.new(status: status, cnpj: nil, confidence: 0.0, error_code: nil, company: nil, **attributes,
               evidence: @evidence + evidence, candidates: @candidate_cnpjs || [])
  end
end
