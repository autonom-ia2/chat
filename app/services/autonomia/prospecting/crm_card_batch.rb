# Envio ao CRM de vários leads de uma vez (#680). Cada lead é um envio independente, na própria transação: a falha de
# um não desfaz os outros. O resumo separa criados agora, já existentes (reenvio não cria nada) e falhas com motivo.
# Lead fora da conta é "não encontrado", igual a lead que não existe, para não revelar nada de outra conta.
class Autonomia::Prospecting::CrmCardBatch
  MAX_LEADS = 30

  Result = Struct.new(:created, :existing, :failed, keyword_init: true)

  class Error < StandardError; end
  class TooManyLeads < Error; end
  class NoLeads < Error; end

  def initialize(account:, user:, lead_ids:, pipeline_id:, stage_id:)
    @account = account
    @user = user
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
    @pipeline_id = pipeline_id
    @stage_id = stage_id
  end

  def perform
    raise NoLeads, 'prospecting.crm_send.no_leads' if @lead_ids.empty?
    raise TooManyLeads, 'prospecting.crm_send.too_many_leads' if @lead_ids.size > MAX_LEADS
    raise Autonomia::Prospecting::CrmCardConverter::Error, 'CRM is disabled' unless ::Crm::Config.enabled?

    ensure_destination!
    result = Result.new(created: [], existing: [], failed: [])
    @lead_ids.each { |lead_id| send_lead(lead_id, result) }
    result
  end

  private

  # Funil e estágio errados valem para o lote inteiro: nada é tentado.
  def ensure_destination!
    pipeline = @account.crm_pipelines.active.find(@pipeline_id)
    @account.crm_pipeline_stages.where(pipeline: pipeline).find(@stage_id)
  end

  def leads_by_id
    @leads_by_id ||= Autonomia::Prospecting::Lead.where(account: @account, id: @lead_ids).index_by(&:id)
  end

  def send_lead(lead_id, result)
    lead = leads_by_id[lead_id]
    return result.failed << failure(lead_id, 'not_found') if lead.nil?

    record(convert(lead), result)
  rescue ActiveRecord::RecordInvalid
    result.failed << failure(lead_id, 'invalid_data')
  rescue StandardError => e
    Rails.logger.error("[prospecting.crm_send] lead=#{lead_id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    result.failed << failure(lead_id, 'unexpected_error')
  end

  def convert(lead)
    Autonomia::Prospecting::CrmCardConverter.new(lead: lead, user: @user, pipeline_id: @pipeline_id, stage_id: @stage_id).perform
  end

  def record(converted, result)
    return result.existing << { lead_id: converted.lead.id, card_id: converted.card.id } unless converted.created

    result.created << { lead_id: converted.lead.id, card_id: converted.card.id, contact_id: converted.contact&.id, company_id: converted.company&.id }
  end

  def failure(lead_id, reason_code)
    { lead_id: lead_id, reason_code: reason_code, message: I18n.t("autonomia.prospecting.crm_send.failures.#{reason_code}") }
  end
end
