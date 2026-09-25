# Reaproveitamento da pesquisa (#679): o lugar já pesquisado há menos de 90 dias, por este lead ou pelo mesmo lugar em
# outra conta, não paga a descoberta de novo. Devolve o perfil e a confiança da identificação que o achou, ou nil.
#
# without_company cobre a outra metade da trava por empresa: se a pesquisa do mesmo lugar que segurava a trava terminou
# sem empresa (no_result ou ambiguous) depois deste pedido, o desfecho dela vale para este lead, sem nova chamada à
# BigDataCorp. Só o desfecho concorrente: um "não achei" antigo não impede pesquisar de novo.
class Autonomia::Prospecting::Research::Reuse
  Source = Struct.new(:profile, :confidence, :evidence, keyword_init: true)
  WITHOUT_COMPANY = %w[no_result ambiguous].freeze

  def initialize(lead:, requested_role:)
    @lead = lead
    @requested_role = requested_role
  end

  def find(since:)
    source_leads.each do |lead|
      profile = lead.company_profile
      next unless profile&.verified_since?(since) && profile.owner_selection_for?(@requested_role)

      research = lead.metadata.to_h['research'].to_h
      return Source.new(profile: profile, confidence: research['company_confidence'], evidence: research['discovery_evidence'])
    end
    nil
  end

  # Outcome sem empresa do mesmo lugar, concluído a partir de `since` (o pedido deste lead), ou nil.
  def without_company(since:)
    return nil if since.nil? || @lead.provider_place_id.blank?

    source = same_place.where(company_research_status: WITHOUT_COMPANY, research_completed_at: since..)
                       .order(research_completed_at: :desc).first
    source && outcome_without_company(source)
  end

  private

  def outcome_without_company(source)
    research = source.metadata.to_h['research'].to_h
    Autonomia::Prospecting::Research::Outcome.new(
      company_status: source.company_research_status, decision_status: source.decision_research_status,
      no_decision_reason: research['no_decision_reason'], confidence: research['company_confidence'], reused: true,
      evidence: research['discovery_evidence'], candidates: research['candidates']
    )
  end

  def same_place
    Autonomia::Prospecting::Lead.where(provider: @lead.provider, provider_place_id: @lead.provider_place_id).where.not(id: @lead.id)
  end

  # O próprio lead primeiro; depois o mesmo lugar em qualquer conta, do perfil verificado mais recente.
  def source_leads
    own = @lead.company_profile_id.present? ? [@lead] : []
    return own if @lead.provider_place_id.blank?

    confirmed = same_place.includes(:company_profile).where(company_research_status: 'confirmed')
                          .where.not(company_profile_id: nil).order(research_completed_at: :desc).limit(5)
    own + confirmed
  end
end
