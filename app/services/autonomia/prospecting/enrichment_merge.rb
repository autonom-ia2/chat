# Junta o resultado de um enriquecimento com o que o lead já tem (#678, E2 frente D). O que o site ou a IA trouxe
# agora vence; o que não trouxe fica como estava: um segundo enriquecimento sem o WhatsApp, o CNPJ, o e-mail, as
# redes ou o decisor não apaga o que o primeiro achou.
class Autonomia::Prospecting::EnrichmentMerge
  CONTACT_FIELDS = {
    enriched_email: 'email',
    enriched_whatsapp: 'whatsapp',
    enriched_instagram: 'instagram',
    enriched_facebook: 'facebook',
    enriched_linkedin: 'linkedin',
    enriched_cnpj: 'cnpj'
  }.freeze
  DECISION_FIELDS = %i[decision_name decision_role decision_confidence decision_source_url].freeze
  # Chaves do scraper que não são dado do site: sozinhas, a página não trouxe nada.
  SCRAPE_BOOKKEEPING_KEYS = %w[website scraped_at truncated source_urls].freeze
  CONFIDENT_DECISION = 0.6

  def initialize(lead:, scraped:, ai_data:)
    @lead = lead
    @scraped = scraped
    @ai = ai_data
  end

  # Falso quando nem o site nem a IA trouxeram algo que o vendedor use: aí o enriquecimento é falha, não "enriquecido".
  def useful?
    @scraped.except(*SCRAPE_BOOKKEEPING_KEYS).compact_blank.present? || useful_ai?
  end

  def attributes
    {
      enrichment_status: 'completed',
      enrichment_completed_at: Time.current,
      enrichment_error: nil,
      enrichment_failed_attempts: 0,
      enrichment_source: useful_ai? ? 'site_and_autonomia_ai' : 'site',
      enriched_data: enriched_data,
      decision_linkedin: first_present(@ai['decision_linkedin'], @scraped['linkedin'], @lead.decision_linkedin),
      decision_instagram: first_present(@ai['decision_instagram'], @scraped['instagram'], @lead.decision_instagram),
      enrichment_summary: first_present(@ai['summary'], summary_from_scrape, @lead.enrichment_summary),
      **contact_fields,
      **decision_fields
    }
  end

  private

  def useful_ai?
    confident_decision? || @ai.slice('summary', 'decision_linkedin', 'decision_instagram').compact_blank.present?
  end

  # O erro gravado por uma rodada antiga sai; a IA desta rodada vence quando trouxe algo.
  def enriched_data
    previous = @lead.enriched_data.to_h.except('error', 'message')
    previous.merge(@scraped.compact_blank).merge('ai' => @ai.compact.presence || previous['ai'] || {})
  end

  def contact_fields
    CONTACT_FIELDS.to_h { |column, key| [column, first_present(@scraped[key], @lead.public_send(column))] }
  end

  # Decisor confiante novo substitui o anterior inteiro; sem ele, o decisor que já havia fica. Sem nenhum dos dois,
  # guarda só a confiança que a IA deu.
  def decision_fields
    if confident_decision?
      { decision_name: @ai['decision_name'], decision_role: @ai['decision_role'],
        decision_confidence: @ai['decision_confidence'], decision_source_url: @ai['decision_source_url'] }
    elsif @lead.decision_name.present?
      DECISION_FIELDS.index_with { |field| @lead.public_send(field) }
    else
      { decision_name: nil, decision_role: nil, decision_confidence: @ai['decision_confidence'], decision_source_url: nil }
    end
  end

  def confident_decision?
    @ai['decision_name'].present? && @ai['decision_confidence'].to_f >= CONFIDENT_DECISION
  end

  def summary_from_scrape
    [@scraped['title'], @scraped['description']].compact_blank.join(' - ').presence
  end

  def first_present(*values)
    values.find(&:present?)
  end
end
