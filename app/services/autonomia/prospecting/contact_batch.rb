# Criar contatos em lote (#732, item 10): o mesmo ContactConverter do contato de um lead só, um lead por vez e cada um
# na própria transação, com o resumo no formato do envio ao CRM (criados, já existentes, falhas com motivo). Lead
# descartado não vira contato; lead fora da conta é "não encontrado", igual a lead que não existe.
class Autonomia::Prospecting::ContactBatch
  MAX_LEADS = 30

  Result = Struct.new(:created, :existing, :failed, keyword_init: true)

  class Error < StandardError; end
  class TooManyLeads < Error; end
  class NoLeads < Error; end

  def initialize(account:, user:, lead_ids:)
    @account = account
    @user = user
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
  end

  def perform
    raise NoLeads, 'no_leads' if @lead_ids.empty?
    raise TooManyLeads, 'too_many_leads' if @lead_ids.size > MAX_LEADS

    result = Result.new(created: [], existing: [], failed: [])
    @lead_ids.each { |lead_id| convert_lead(lead_id, result) }
    result
  end

  private

  def leads_by_id
    @leads_by_id ||= Autonomia::Prospecting::Lead.where(account: @account, id: @lead_ids).index_by(&:id)
  end

  def convert_lead(lead_id, result)
    lead = leads_by_id[lead_id]
    return result.failed << failure(lead_id, 'not_found') if lead.nil?
    return result.failed << failure(lead_id, 'discarded') if lead.discarded?

    record(Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user).perform, result)
  rescue ActiveRecord::RecordInvalid
    result.failed << failure(lead_id, 'invalid_data')
  rescue StandardError => e
    Rails.logger.error("[prospecting.contact_batch] lead=#{lead_id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    result.failed << failure(lead_id, 'unexpected_error')
  end

  def record(converted, result)
    (converted.created ? result.created : result.existing) << { lead_id: converted.lead.id, contact_id: converted.contact.id }
  end

  def failure(lead_id, reason_code)
    { lead_id: lead_id, reason_code: reason_code, message: I18n.t("autonomia.prospecting.contact_batch.failures.#{reason_code}") }
  end
end
