# Bloco `research` do lead na API e no evento prospecting.lead.updated (#679, contrato com a tela).
#
# Empresa, sócios e decisor só aparecem com a empresa confirmada: um desfecho novo sem empresa (ou uma falha) não
# mostra o cadastro de uma pesquisa anterior, que continua gravado. O decisor é o da pesquisa, nunca o nome que a IA
# gravou antes dela.
#
# Empresa e data de verificação vêm do retrato que a pesquisa do lead gravou (metadata research), na mesma época dos
# donos e do decisor: o perfil da empresa é compartilhado e outra conta o regrava. Lead pesquisado antes do retrato
# existir cai no perfil.
module Autonomia::Prospecting::Research::Payload
  COMPANY_FIELDS = %w[cnpj legal_name trade_name registration_status registration_state legal_nature_text].freeze
  FOUND = %w[confirmed possible].freeze
  WITHOUT_DECISION = %w[no_result ambiguous].freeze

  module_function

  def build(lead)
    research = lead.metadata.to_h['research'].to_h
    profile = FOUND.include?(lead.company_research_status) ? lead.company_profile : nil
    states(lead).merge(
      verified_at: verified_at(profile, research),
      no_decision_reason: WITHOUT_DECISION.include?(lead.decision_research_status) ? research['no_decision_reason'] : nil,
      company: company(profile, research),
      owners: profile ? Array(research['owners']) : [],
      decision: decision(lead, profile, research)
    )
  end

  def verified_at(profile, research)
    return unless profile

    research['verified_at'].presence || profile.verified_at&.iso8601
  end

  def company(profile, research)
    return unless profile

    research['company'].presence || profile.attributes.slice(*COMPANY_FIELDS)
  end

  def states(lead)
    {
      company_status: lead.company_research_status, decision_status: lead.decision_research_status, reused: lead.research_reused,
      requested_at: lead.research_requested_at&.iso8601, completed_at: lead.research_completed_at&.iso8601, error_code: lead.research_error
    }
  end

  def decision(lead, profile, research)
    return unless profile && FOUND.include?(lead.decision_research_status) && lead.decision_name.present?

    { name: lead.decision_name, role: lead.decision_role, confidence: lead.decision_confidence&.to_f,
      source: research['decision_source'], verified_at: verified_at(profile, research) }
  end
end
