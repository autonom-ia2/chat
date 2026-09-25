# Grava o desfecho da pesquisa no lead (#679), só nas colunas da pesquisa e do decisor, com a linha travada: o
# enriquecimento e a verificação de WhatsApp gravam o mesmo lead em paralelo.
#
# - enriched_cnpj não é tocado: é o CNPJ que o site mostrou. O do cadastro fica no perfil da empresa (company_profile_id),
#   e é dele que a tela mostra. Gravar o CNPJ aceito ali fazia a próxima pesquisa lê-lo como sinal do site e se
#   corroborar sozinha, travando um CNPJ errado no "verificar novamente";
# - confiança só com nome, e a do decisor é a da identificação da empresa;
# - decision_source_url nunca é a rede da empresa: a fonte do dono é o cadastro, sem link;
# - decisor novo solta as redes do decisor anterior daquele lead; nada de limpeza em massa;
# - sem decisor, o que o lead já tinha fica (decisão do Rodrigo: não apagar nada).
class Autonomia::Prospecting::Research::LeadWriter
  def initialize(lead)
    @lead = lead
  end

  def write(outcome)
    Autonomia::Prospecting::Lead.transaction do
      @lead.lock!
      @lead.update_columns(attributes(outcome)) # rubocop:disable Rails/SkipsModelValidations -- só as colunas da pesquisa
    end
  end

  private

  def attributes(outcome)
    now = Time.current
    attributes = {
      company_research_status: outcome.company_status, decision_research_status: outcome.decision_status,
      research_completed_at: now, research_reused: outcome.reused, research_error: outcome.error_code, updated_at: now
    }
    # Falha técnica não apaga o que uma pesquisa anterior achou: só o estado e o código mudam.
    return attributes if outcome.failure?

    attributes[:metadata] = @lead.metadata.to_h.merge('research' => research_metadata(outcome))
    attributes.merge(profile_attributes(outcome.profile)).merge(decision_attributes(outcome))
  end

  def research_metadata(outcome)
    {
      'owners' => outcome.profile&.owners || [], 'no_decision_reason' => outcome.no_decision_reason,
      'decision_source' => outcome.profile&.data&.dig('decision_source'), 'company_confidence' => outcome.confidence,
      'discovery_evidence' => Array(outcome.evidence).as_json, 'candidates' => Array(outcome.candidates)
    }
  end

  def profile_attributes(profile)
    return {} if profile.nil?

    { company_profile_id: profile.id }
  end

  def decision_attributes(outcome)
    decision = outcome.decision
    return {} if decision.blank? || decision['name'].blank?

    attributes = { decision_name: decision['name'], decision_role: decision['qualification'],
                   decision_confidence: confidence(outcome.confidence), decision_source_url: nil }
    return attributes if @lead.decision_name == decision['name']

    attributes.merge(decision_linkedin: nil, decision_instagram: nil)
  end

  def confidence(value)
    value&.to_f&.clamp(0.0, 1.0)&.round(2)
  end
end
