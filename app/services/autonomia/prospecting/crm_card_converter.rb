# Leva um lead da prospecção ao funil (#680): empresa, contato e card numa transação só, e depois do commit a automação
# de entrada do estágio, uma vez, só para o card criado agora. O Crm::Cards::Creator não dispara automação para
# ninguém; quem liga a automação do card da prospecção é este serviço.
class Autonomia::Prospecting::CrmCardConverter
  Result = Struct.new(:lead, :card, :created, :contact, :company, keyword_init: true)

  class Error < StandardError; end

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

    ::Crm::Cards::Broadcaster.broadcast(result.card, ::Events::Types::CRM_CARD_CREATED)
    run_stage_automation(result.card, stage)
    result
  rescue ActiveRecord::RecordNotUnique
    # Outro envio do mesmo lead ganhou a corrida pelo external_id: o card dele é o card deste lead.
    card = @account.crm_cards.find_by(external_id: external_id)
    raise if card.blank?

    existing_result(card)
  end

  private

  def find_stage
    pipeline = @account.crm_pipelines.active.find(@pipeline_id)
    @account.crm_pipeline_stages.where(pipeline: pipeline).find(@stage_id)
  end

  # Uma transação por lead: no envio em lote, a falha de um lead desfaz a empresa e o contato só dele.
  def create_all(stage)
    ActiveRecord::Base.transaction do
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
      description: description,
      source: 'autonomia_prospecting',
      external_id: external_id,
      metadata: metadata(company)
    }
  end

  def external_id
    "autonomia_prospecting_lead:#{@lead.id}"
  end

  def description
    [
      @lead.category,
      @lead.website,
      [@lead.address, @lead.city, @lead.state, @lead.country].compact_blank.join(', '),
      @lead.enrichment_summary
    ].compact_blank.join("\n")
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
