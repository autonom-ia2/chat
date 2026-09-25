class Autonomia::Prospecting::LeadEnricher
  class Error < StandardError; end

  AI_SCHEMA = {
    name: 'autonomia_prospecting_lead_enrichment',
    schema: {
      type: 'object',
      additionalProperties: false,
      properties: {
        decision_name: { type: %w[string null] },
        decision_role: { type: %w[string null] },
        decision_confidence: { type: 'number', minimum: 0, maximum: 1 },
        decision_source_url: { type: %w[string null] },
        decision_linkedin: { type: %w[string null] },
        decision_instagram: { type: %w[string null] },
        summary: { type: %w[string null] },
        signals: {
          type: 'array',
          items: { type: 'string' }
        }
      },
      required: [
        'decision_name',
        'decision_role',
        'decision_confidence',
        'decision_source_url',
        'decision_linkedin',
        'decision_instagram',
        'summary',
        'signals'
      ]
    }
  }.freeze

  # `user` fica por compatibilidade com o controller; o enriquecimento não depende de quem pediu.
  def initialize(lead:, user: nil)
    @lead = lead
    @user = user
  end

  # Site fora do ar, bloqueado ou vazio, ou nada útil nem do site nem da IA: o lead fica `failed` com o código em
  # `enrichment_error` e a tentativa contada, sem apagar o que um enriquecimento anterior achou. Não levanta: é um
  # desfecho, não uma quebra.
  def perform
    raise Error, 'prospecting.enrichment.disabled' unless research_allowed?

    @lead.update!(
      enrichment_status: 'running',
      enrichment_requested_at: Time.current,
      enrichment_error: nil
    )

    scraped_data = scrape_website
    return record_failed_attempt(scraped_data['error']) if scraped_data['error'].present?

    merge = Autonomia::Prospecting::EnrichmentMerge.new(lead: @lead, scraped: scraped_data, ai_data: enrich_with_ai(scraped_data))
    return record_failed_attempt('empty_result') unless merge.useful?

    @lead.update!(merge.attributes)
    @lead.reload
  rescue Error => e
    mark_failed(e.message)
    raise
  rescue StandardError => e
    mark_failed(e.message, count_attempt: true)
    raise Error, e.message
  end

  private

  # O enriquecimento é pesquisa: só roda com o módulo e a pesquisa ligados pelo superadmin (#683).
  def research_allowed?
    Autonomia::Prospecting::Config.enabled?(@lead.account) && Autonomia::Prospecting::Config.research_enabled?(@lead.account)
  end

  def scrape_website
    return {} if @lead.website.blank?

    Autonomia::Prospecting::WebsiteScraper.new(url: @lead.website).perform.data
  end

  def enrich_with_ai(scraped_data)
    credential = Autonomia::Prospecting::AiCredential.new(account: @lead.account).resolve
    return {} if credential.blank?

    raw = Crm::Ai::ResponsesClient.new(
      credential: credential,
      feature: 'prospecting_lead_enrichment',
      account: @lead.account
    ).create(
      model: Crm::Ai::Config::MODEL_SUMMARY,
      instructions: instructions,
      input: ai_input(scraped_data),
      schema: AI_SCHEMA,
      reasoning_effort: Crm::Ai::Config::SUMMARY_REASONING_EFFORT,
      tools: Crm::Ai::WebSearch.tools,
      timeout: 90
    )
    parsed = JSON.parse(raw[:text])
    parsed.is_a?(Hash) ? parsed : {}
  rescue Crm::Ai::ResponsesClient::Error, JSON::ParserError => e
    Rails.logger.warn(
      "[Autonomia::Prospecting] lead enrichment AI skipped lead_id=#{@lead.id} error=#{e.class.name}"
    )
    {}
  end

  def instructions
    <<~PROMPT
      Você enriquece leads B2B brasileiros para prospecção comercial.

      Regras:
      - Retorne somente JSON no schema solicitado.
      - Não invente nomes, cargos, redes sociais ou fontes.
      - Preencha decisor apenas se houver fonte explícita no site ou em busca web.
      - decision_confidence deve ser 0 quando não houver decisor.
      - Use decision_source_url apenas quando a fonte sustentar o decisor.
      - O resumo deve ser curto, objetivo e útil para abordagem comercial.
    PROMPT
  end

  def ai_input(scraped_data)
    {
      lead: {
        name: @lead.name,
        website: @lead.website,
        phone: @lead.phone,
        address: @lead.address,
        city: @lead.city,
        state: @lead.state,
        category: @lead.category,
        rating: @lead.rating,
        reviews_count: @lead.reviews_count
      },
      scraped_site_data: scraped_data.slice(
        'title',
        'description',
        'email',
        'phone',
        'whatsapp',
        'instagram',
        'facebook',
        'linkedin',
        'cnpj',
        'text_excerpt',
        'source_urls'
      )
    }.to_json
  end

  def record_failed_attempt(code)
    mark_failed(code, count_attempt: true)
    @lead.reload
  end

  # Só muda status, erro e contador: os dados achados antes ficam.
  def mark_failed(message, count_attempt: false)
    @lead.update_columns(
      enrichment_status: 'failed',
      enrichment_completed_at: Time.current,
      enrichment_error: message.to_s.truncate(255),
      updated_at: Time.current
    )
    # Soma no próprio UPDATE do banco: duas falhas ao mesmo tempo contam duas.
    Autonomia::Prospecting::Lead.update_counters(@lead.id, enrichment_failed_attempts: 1) if count_attempt # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError
    nil
  end
end
