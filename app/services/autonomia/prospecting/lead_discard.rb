# Descartar leads (#732, item 10), no painel do lead e em lote, sempre com motivo. Descartado continua visível na busca,
# marcado, e sai das ações de envio: o CRM (CrmCardBatch), os contatos em lote (ContactBatch) e a campanha
# (CampaignSegmentBuilder) recusam lead descartado. Na campanha já montada, o contato perde a etiqueta do segmento e
# sai dos pendentes da campanha da API do WhatsApp em andamento (SegmentRefusalSync, fora da requisição). Lead fora da
# conta, ou que a pessoa não vê, volta como não encontrado, sem ser tocado.
class Autonomia::Prospecting::LeadDiscard
  MAX_LEADS = 500
  MAX_REASON_LENGTH = 255

  Result = Struct.new(:leads, :missing_lead_ids, keyword_init: true)

  class Error < StandardError; end
  class NoLeads < Error; end
  class TooManyLeads < Error; end
  class MissingReason < Error; end
  class ReasonTooLong < Error; end

  # leads_scope: os leads que quem pede enxerga (Visibility, #732 item 6). O controller sempre passa; sem ele, a conta.
  def initialize(account:, lead_ids:, reason:, leads_scope: nil)
    @account = account
    @leads_scope = leads_scope || Autonomia::Prospecting::Lead.where(account: account)
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
    @reason = reason.to_s.strip
  end

  def perform
    validate!
    leads = @leads_scope.where(id: @lead_ids).to_a
    # Descartar muda só o status: a recusa da pessoa (consent_refused_at) e a marca no contato ficam (chat#713, 26/09).
    Autonomia::Prospecting::Lead.transaction do
      leads.each { |lead| lead.update!(status: :discarded, discard_reason: @reason) }
    end
    # No job da Prospecção, fora da requisição: quem já tinha a etiqueta de um segmento sai dela (a campanha lê o público
    # pela etiqueta mais tarde) e os pendentes da campanha em andamento que o segmento alimentou são cancelados.
    Autonomia::Prospecting::SegmentRefusalSync.enqueue(account: @account, leads: leads)

    Result.new(leads: leads, missing_lead_ids: @lead_ids - leads.map(&:id))
  end

  private

  def validate!
    raise NoLeads, 'no_leads' if @lead_ids.empty?
    raise TooManyLeads, 'too_many_leads' if @lead_ids.size > MAX_LEADS
    raise MissingReason, 'missing_reason' if @reason.empty?
    raise ReasonTooLong, 'reason_too_long' if @reason.length > MAX_REASON_LENGTH
  end
end
