# Leva um lead da prospecção ao funil (#680): empresa, contato e card numa transação só, e depois do commit a automação
# de entrada do estágio, uma vez, só para o card criado agora. O Crm::Cards::Creator não dispara automação para
# ninguém; quem liga a automação do card da prospecção é este serviço.
class Autonomia::Prospecting::CrmCardConverter
  Result = Struct.new(:lead, :card, :created, :contact, :company, keyword_init: true)

  class Error < StandardError; end

  # Mesma faixa do anel de prioridade da tela (prospectingPriority.js): 75+ muito quente, 50+ alta, 25+ morno. Sem
  # prioridade calculada, o card fica no padrão do CRM (média).
  PRIORITY_BANDS = [[75, 'urgent'], [50, 'high'], [25, 'medium']].freeze
  LOWEST_PRIORITY = 'low'.freeze
  DESCRIPTION_SCOPE = 'autonomia.prospecting.crm_send.card_description'.freeze

  def initialize(lead:, user:, pipeline_id:, stage_id:)
    @lead = lead
    @account = lead.account
    @user = user
    @pipeline_id = pipeline_id
    @stage_id = stage_id
  end

  def perform
    return existing_result(@lead.crm_card) if @lead.crm_card.present?

    raise Error, 'CRM is disabled' unless ::Crm::Config.enabled?

    stage = find_stage
    result = create_all(stage)
    return result unless result.created

    ::Crm::Cards::Broadcaster.broadcast(result.card, ::Events::Types::CRM_CARD_CREATED)
    run_stage_automation(result.card, stage)
    result
  rescue ActiveRecord::RecordNotUnique
    # Outro envio do mesmo lead ganhou a corrida pelo external_id: o card dele é o card deste lead.
    card = @account.crm_cards.find_by(external_id: external_id)
    raise if card.blank?

    existing_result(card)
  end

  # O decisor do card (metadata e linha da descrição) com o lead como está agora. O OwnerAdoption usa o mesmo para o
  # card acompanhar o "Usar como contato".
  def decision_snapshot
    { 'decision' => decision, 'line' => decision_line }
  end

  private

  def find_stage
    pipeline = @account.crm_pipelines.active.find(@pipeline_id)
    @account.crm_pipeline_stages.where(pipeline: pipeline).find(@stage_id)
  end

  # Uma transação por lead: no envio em lote, a falha de um lead desfaz a empresa e o contato só dele.
  # A trava do lead vem primeiro, como no ContactConverter e no OwnerAdoption (mesma ordem, sem deadlock com o "Usar
  # como contato"). Envio simultâneo do mesmo lead (duplo clique, duas abas) espera aqui e, depois da trava, acha o card
  # do outro: devolve "já existente", sem automação, em vez de esbarrar no external_id e parecer falha.
  def create_all(stage)
    ActiveRecord::Base.transaction do
      @lead.lock!
      next existing_result(@lead.crm_card) if @lead.crm_card_id.present?

      company = Autonomia::Prospecting::CompanyUpserter.new(lead: @lead).perform.company
      contact = Autonomia::Prospecting::ContactConverter.new(lead: @lead, user: @user, company: company).perform.contact
      card = create_card(stage: stage, contact: contact, company: company)
      @lead.update!(crm_card: card)

      Result.new(lead: @lead.reload, card: card.reload, created: true, contact: contact, company: company)
    end
  end

  def existing_result(card)
    Result.new(lead: @lead.reload, card: card, created: false, contact: card.contact, company: nil)
  end

  def run_stage_automation(card, stage)
    ::Crm::StageAutomations::Runner.new(card: card, actor: @user, from_stage_id: nil, to_stage_id: stage.id).perform
  rescue StandardError => e
    # O card já está gravado e fica; a automação que falhou vai para o log e para o rastreador de erros.
    Rails.logger.error("[prospecting.crm_card] automação de entrada falhou card=#{card.id} lead=#{@lead.id}: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
  end

  def create_card(stage:, contact:, company:)
    ::Crm::Cards::Creator.new(
      account: @account,
      user: @user,
      params: card_params(stage: stage, contact: contact, company: company)
    ).perform
  end

  def card_params(stage:, contact:, company:)
    {
      pipeline_id: stage.pipeline_id,
      stage_id: stage.id,
      contact_id: contact&.id,
      title: @lead.name,
      priority: priority,
      description: description(company),
      source: 'autonomia_prospecting',
      external_id: external_id,
      metadata: metadata(company)
    }
  end

  def external_id
    "autonomia_prospecting_lead:#{@lead.id}"
  end

  def priority
    return if @lead.priority_score.nil?

    value = @lead.priority_score.to_f.round
    PRIORITY_BANDS.find { |minimum, _priority| value >= minimum }&.last || LOWEST_PRIORITY
  end

  # A nota da prospecção vai no texto do card, e não em crm_cards.score: aquela coluna é a nota de conversa da IA do
  # CRM (frio/morno/quente/urgente, com decaimento), outra escala.
  def description(company)
    [
      @lead.category,
      @lead.website,
      [@lead.address, @lead.city, @lead.state, @lead.country].compact_blank.join(', '),
      score_line,
      decision_line,
      *company_lines(company),
      @lead.enrichment_summary
    ].compact_blank.join("\n")
  end

  def score_line
    I18n.t('score', scope: DESCRIPTION_SCOPE, score: @lead.score.to_f.round) if @lead.score.present?
  end

  def decision_line
    person = decision
    return if person.blank? || person['name'].blank?
    return I18n.t('decision', scope: DESCRIPTION_SCOPE, name: person['name']) if person['role'].blank?

    I18n.t('decision_with_role', scope: DESCRIPTION_SCOPE, name: person['name'], role: person['role'])
  end

  def company_lines(company)
    summary = company_summary(company).to_h
    [
      summary['legal_name'].presence && I18n.t('legal_name', scope: DESCRIPTION_SCOPE, legal_name: summary['legal_name']),
      summary['cnpj'].presence && I18n.t('cnpj', scope: DESCRIPTION_SCOPE, cnpj: summary['cnpj'])
    ]
  end

  def metadata(company)
    {
      'autonomia_prospecting' => {
        'lead_id' => @lead.id,
        'provider' => @lead.provider,
        'provider_place_id' => @lead.provider_place_id,
        'rating' => @lead.rating&.to_f,
        'reviews_count' => @lead.reviews_count,
        'score' => @lead.score&.to_f,
        'priority_score' => @lead.priority_score&.to_f,
        'search_rank' => @lead.search_rank,
        'decision' => decision,
        'company' => company_summary(company),
        'summary' => @lead.enrichment_summary,
        'source' => 'autonomia_prospecting'
      }
    }
  end

  # O decisor é o da pesquisa (#679). Lead que nunca foi pesquisado mantém o decisor que o enriquecimento achou.
  def decision
    return @decision if defined?(@decision)

    @decision = decision_from_lead
  end

  def decision_from_lead
    researched = Autonomia::Prospecting::Research::Payload.build(@lead)[:decision]
    return { 'name' => researched[:name], 'role' => researched[:role], 'confidence' => researched[:confidence] } if researched
    return unless @lead.decision_research_status == 'not_researched' && @lead.decision_name.present?

    { 'name' => @lead.decision_name, 'role' => @lead.decision_role, 'confidence' => @lead.decision_confidence&.to_f }
  end

  def company_summary(company)
    return if company.blank?

    attributes = company.additional_attributes.to_h
    { 'id' => company.id, 'cnpj' => attributes['cnpj'], 'legal_name' => attributes['legal_name'] }
  end
end
