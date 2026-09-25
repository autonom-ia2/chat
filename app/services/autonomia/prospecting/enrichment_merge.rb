# Junta o resultado de um enriquecimento com o que o lead já tem (#678, E2 frente D). O que o site ou a IA trouxe
# agora vence; o que não trouxe fica como estava: um segundo enriquecimento sem o WhatsApp, o CNPJ, o e-mail ou as
# redes não apaga o que o primeiro achou.
#
# O decisor não é mais do enriquecimento (#679): quem decide sai do quadro de sócios, pela pesquisa de empresa e
# decisor. Daqui não sai nome, cargo, confiança, fonte nem rede de decisor, e o palpite da IA não fica guardado.
# O decisor da IA continua acessível para o gabarito em LeadEnricher.ai_decision.
class Autonomia::Prospecting::EnrichmentMerge
  CONTACT_FIELDS = {
    enriched_email: 'email',
    enriched_whatsapp: 'whatsapp',
    enriched_instagram: 'instagram',
    enriched_facebook: 'facebook',
    enriched_linkedin: 'linkedin',
    enriched_cnpj: 'cnpj'
  }.freeze
  SOCIAL_KEYS = %w[instagram facebook linkedin].freeze
  # Chaves do scraper que não são dado do site: sozinhas, a página não trouxe nada.
  SCRAPE_BOOKKEEPING_KEYS = %w[website scraped_at truncated source_urls].freeze
  # Chaves da resposta da IA que falam de uma pessoa: não entram no lead.
  AI_DECISION_KEYS = %w[decision_name decision_role decision_confidence decision_source_url decision_linkedin decision_instagram].freeze
  # Régua do decisor da IA, usada só pelo gabarito (LeadEnricher.ai_decision).
  CONFIDENT_DECISION = 0.6

  def initialize(lead:, scraped:, ai_data:)
    @lead = lead
    @scraped = scraped
    @ai = ai_data.except(*AI_DECISION_KEYS)
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
      enrichment_summary: first_present(@ai['summary'], summary_from_scrape, @lead.enrichment_summary),
      **contact_fields
    }
  end

  private

  def useful_ai?
    @ai['summary'].present?
  end

  # O erro gravado por uma rodada antiga sai; a IA desta rodada vence quando trouxe algo.
  def enriched_data
    previous = @lead.enriched_data.to_h.except('error', 'message')
    previous.merge(@scraped.compact_blank).merge('ai' => @ai.compact.presence || previous['ai'] || {})
  end

  # Link de rede raspado do site maior que a coluna não derruba o enriquecimento do lead (#723).
  def contact_fields
    CONTACT_FIELDS.to_h do |column, key|
      [column, first_present(scraped_contact(key), @lead.public_send(column))]
    end
  end

  def scraped_contact(key)
    value = @scraped[key]
    SOCIAL_KEYS.include?(key) ? Autonomia::Prospecting::ColumnFit.url(value, drop_query: false) : value
  end

  def summary_from_scrape
    [@scraped['title'], @scraped['description']].compact_blank.join(' - ').presence
  end

  def first_present(*values)
    values.find(&:present?)
  end
end
