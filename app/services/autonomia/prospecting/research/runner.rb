# Pesquisa de empresa e decisor de um lead (#679): descoberta do CNPJ (BigDataCorp, frente A) -> cadastro público ->
# regra do dono (frente B), sem IA. Porta o fluxo do Orth (lib/services/research/company-owner/pipeline.ts) sem a parte
# de custo e crédito (decisão do Rodrigo).
#
# Devolve :done (desfecho gravado no lead) ou :waiting (outra pesquisa da mesma empresa está rodando; o job tenta de
# novo e reaproveita o que ela gravar). Falhas tipadas das frentes A e B viram failed/blocked com o código: a descoberta
# devolve Result com error_code, o cadastro devolve Registry::Failure (valor, não exceção). O resto sobe para o job, que
# marca interrupted.
class Autonomia::Prospecting::Research::Runner
  R = Autonomia::Prospecting::Research

  def initialize(lead:, force: false)
    @lead = lead
    @force = force
  end

  def perform
    return finish(R::Outcome.failure('blocked', 'research_disabled')) unless research_enabled?

    reusable = @force ? nil : reuse.find(since: reuse_cutoff)
    return finish(reused(reusable)) if reusable

    researched = R::CompanyLock.synchronize(@lead) { research }
    return :done if researched

    mark(R::States::WAITING_CAPACITY)
    :waiting
  end

  private

  def research
    mark(R::States::RESEARCHING, started: true)
    # Outra pesquisa da mesma empresa pode ter gravado enquanto este pedido esperava a trava.
    reusable = reuse.find(since: @force ? @lead.research_requested_at || Time.current : reuse_cutoff)
    finish(reusable ? reused(reusable) : discover)
  rescue R::PersonFields::Violation
    finish(R::Outcome.failure('failed', 'person_fields_violation'))
  end

  def discover
    discovery = R::CnpjDiscovery.new(lead: @lead).perform
    case discovery.status
    when :found then with_company(discovery)
    when :not_found then R::Outcome.without_company('no_result', 'company_not_found', discovery)
    when :ambiguous then R::Outcome.without_company('ambiguous', 'company_ambiguous', discovery)
    when :not_configured then R::Outcome.failure('blocked', discovery.error_code.presence || 'not_configured')
    else R::Outcome.failure('failed', discovery.error_code.presence || 'discovery_failed')
    end
  end

  # CNPJ achado: o cadastro verificado há menos de 90 dias vale; senão usa o cadastro que a descoberta já leu (a frente A
  # confere cidade e UF nele antes de aceitar o candidato) ou consulta de novo, e grava o perfil.
  def with_company(discovery)
    cnpj = R::ProfileAttributes.digits(discovery.cnpj)
    profile = Autonomia::Prospecting::CompanyProfile.find_by(cnpj: cnpj)
    unless fresh_profile?(profile)
      company = registry_company(cnpj, discovery.company)
      return R::Outcome.failure('failed', "REGISTRY_#{company.reason.to_s.upcase}") if company.failed?

      profile = save_profile(company)
    end
    R::Outcome.with_profile(profile, confidence: discovery.confidence, reused: false, evidence: discovery.evidence,
                                     candidates: discovery.candidates)
  end

  def registry_company(cnpj, known)
    return known if known.respond_to?(:failed?) && !known.failed? && R::ProfileAttributes.digits(known.cnpj) == cnpj

    R::Registry.fetch(cnpj)
  end

  def save_profile(company)
    selection = R::OwnerPolicy.select(company: company, requested_role: requested_role)
    attributes = R::ProfileAttributes.build(company, selection: selection, requested_role: requested_role, verified_at: Time.current)
    Autonomia::Prospecting::CompanyProfile.upsert(attributes, unique_by: :cnpj) # rubocop:disable Rails/SkipsModelValidations
    Autonomia::Prospecting::CompanyProfile.find_by!(cnpj: attributes[:cnpj])
  end

  def fresh_profile?(profile)
    !@force && profile.present? && profile.verified_since?(reuse_cutoff) && profile.owner_selection_for?(requested_role)
  end

  def reused(source)
    R::Outcome.with_profile(source.profile, confidence: source.confidence, reused: true, evidence: source.evidence)
  end

  def finish(outcome)
    R::LeadWriter.new(@lead).write(outcome)
    :done
  end

  def mark(status, started: false)
    attributes = { company_research_status: status, decision_research_status: status, updated_at: Time.current }
    attributes[:research_started_at] = Time.current if started
    @lead.update_columns(attributes) # rubocop:disable Rails/SkipsModelValidations -- estado da pesquisa, sem tocar no resto
    Autonomia::Prospecting::Lead.update_counters(@lead.id, research_attempts: 1) if started # rubocop:disable Rails/SkipsModelValidations
    Autonomia::Prospecting::LeadBroadcaster.updated(@lead.reload)
  end

  def reuse
    @reuse ||= R::Reuse.new(lead: @lead, requested_role: requested_role)
  end

  def reuse_cutoff
    Autonomia::Prospecting::CompanyProfile::REUSE_WINDOW.ago
  end

  def requested_role
    Autonomia::Prospecting::DecisionMakerType.normalize(@lead.search&.metadata.to_h['decision_maker_type'])
  end

  def research_enabled?
    Autonomia::Prospecting::Config.enabled?(@lead.account) && Autonomia::Prospecting::Config.research_enabled?(@lead.account)
  end
end
