# Desfecho de uma pesquisa (#679), o que LeadWriter grava no lead. `profile` é o perfil da empresa já gravado;
# `confidence` é a da identificação da empresa (descoberta do CNPJ), a mesma que o decisor herda.
Autonomia::Prospecting::Research::Outcome = Struct.new(
  :company_status, :decision_status, :error_code, :no_decision_reason, :profile, :confidence, :evidence, :candidates, :reused,
  :candidate_scores,
  keyword_init: true
) do
  def self.failure(status, error_code)
    new(company_status: status, decision_status: status, error_code: error_code, reused: false)
  end

  # Sem empresa não há decisor: os dois estados andam juntos.
  def self.without_company(status, reason, discovery)
    new(company_status: status, decision_status: status, no_decision_reason: reason, reused: false,
        evidence: discovery.evidence, candidates: discovery.candidates, confidence: discovery.confidence,
        candidate_scores: discovery.candidate_scores)
  end

  def self.with_profile(profile, confidence:, reused:, evidence: nil, candidates: nil)
    decision = profile.owners.first
    new(company_status: 'confirmed', decision_status: decision ? 'confirmed' : 'no_result', profile: profile,
        no_decision_reason: decision ? nil : profile.data['no_decision_reason'], confidence: confidence, reused: reused,
        evidence: evidence, candidates: candidates)
  end

  def failure?
    %w[failed blocked].include?(company_status)
  end

  def decision
    profile&.owners&.first if decision_status == 'confirmed'
  end
end
