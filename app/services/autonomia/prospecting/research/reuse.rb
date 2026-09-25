# Reaproveitamento da pesquisa (#679): o lugar já pesquisado há menos de 90 dias, por este lead ou pelo mesmo lugar em
# outra conta, não paga a descoberta de novo. Devolve o perfil e a confiança da identificação que o achou, ou nil.
class Autonomia::Prospecting::Research::Reuse
  Source = Struct.new(:profile, :confidence, :evidence, keyword_init: true)

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

  private

  # O próprio lead primeiro; depois o mesmo lugar em qualquer conta, do perfil verificado mais recente.
  def source_leads
    own = @lead.company_profile_id.present? ? [@lead] : []
    return own if @lead.provider_place_id.blank?

    same_place = Autonomia::Prospecting::Lead.includes(:company_profile)
                                             .where(provider: @lead.provider, provider_place_id: @lead.provider_place_id)
                                             .where(company_research_status: 'confirmed').where.not(id: @lead.id)
                                             .where.not(company_profile_id: nil).order(research_completed_at: :desc).limit(5)
    own + same_place
  end
end
