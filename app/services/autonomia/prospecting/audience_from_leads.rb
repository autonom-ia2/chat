# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): os leads escolhidos viram um Público de Campanhas
# (CampaignImport do fluxo audience, source 'prospecting'), gravado pelo CampaignJourney::AudienceWriter, o mesmo do
# Público por conversa. Na tela nova, substitui o segmento por etiqueta (CampaignSegmentBuilder).
#
# - Contato e empresa saem do ContactConverter (que chama o CompanyUpserter), um lead por vez e cada um na própria
#   transação, como o "Criar contatos" (ContactBatch): com decisor, o contato é a pessoa; sem decisor, a empresa, com o
#   mesmo nome; o contato fica ligado à empresa.
# - Fica de fora, com o motivo e sem gravar contato: lead que não existe ou que a pessoa não vê (not_found), o
#   descartado, o que recusou ou cujo contato recusou ou está bloqueado (SegmentEligibility#consent_block_reason), e
#   quem não tem telefone nem e-mail (no_channel).
# - Depois do contato vale a régua de todo Público (ConversationAudience::Reach): telefone OU e-mail do contato, e
#   nunca quem pediu para não receber. O contato que ainda assim fica sem canal (o telefone já era de outro contato)
#   sai com no_channel; ele continua criado, como no "Criar contatos".
# - O Público é gravado de uma vez, no fim. Recusa do writer (contato apagado no meio, por exemplo) sobe como
#   CampaignJourney::AudienceWriter::Error; os contatos já criados ficam.
class Autonomia::Prospecting::AudienceFromLeads
  # O mesmo teto do "Adicionar à campanha" da seleção, que também convertia cada lead na hora.
  MAX_LEADS = Autonomia::Prospecting::SelectionCampaignSegment::MAX_LEADS
  SOURCE = 'prospecting'.freeze
  NO_CHANNEL = 'no_channel'.freeze
  REACH_REASONS = {
    ConversationAudience::Reach::OPTED_OUT => 'opt_out',
    ConversationAudience::Reach::NO_CONTACT => NO_CHANNEL
  }.freeze

  Result = Struct.new(:audience, :entered_lead_ids, :left_out, keyword_init: true)

  # Recusa do pedido inteiro. left_out: quem ficou de fora e por quê, para a tela explicar mesmo quando ninguém entra.
  class Error < StandardError
    attr_reader :left_out

    def initialize(message, left_out: [])
      super(message)
      @left_out = left_out
    end
  end

  # leads_scope: os leads que quem pede enxerga (Visibility, #732 item 6). O controller sempre passa; sem ele, a conta.
  def initialize(account:, user:, lead_ids:, name:, leads_scope: nil)
    @account = account
    @user = user
    @leads_scope = leads_scope || Autonomia::Prospecting::Lead.where(account: account)
    @lead_ids = Array(lead_ids).map(&:to_i).uniq
    @name = name.to_s.strip
  end

  def perform
    raise Error, 'no_leads' if @lead_ids.empty?
    raise Error, 'too_many_leads' if @lead_ids.size > MAX_LEADS
    raise Error, 'name_required' if @name.blank?

    rows = {}
    left_out = []
    @lead_ids.each { |lead_id| place(lead_id, rows, left_out) }
    raise Error.new('no_rows', left_out: left_out) if rows.empty?

    audience = writer.perform(@name, rows.values)
    Result.new(audience: audience, entered_lead_ids: rows.keys, left_out: left_out)
  end

  private

  # Põe o lead nas linhas do Público ou em left_out, com o motivo.
  def place(lead_id, rows, left_out)
    lead = leads_by_id[lead_id]
    reason = lead.nil? ? 'not_found' : reason_before_contact(lead)
    return left_out << left(lead_id, reason) if reason

    contact = convert(lead)
    reason = REACH_REASONS[ConversationAudience::Reach.reason_for(contact)]
    return left_out << left(lead_id, reason) if reason

    rows[lead_id] = row_for(contact)
  rescue ActiveRecord::RecordInvalid
    left_out << left(lead_id, 'invalid_data')
  rescue StandardError => e
    Rails.logger.error("[prospecting.audience_from_leads] lead=#{lead_id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    left_out << left(lead_id, 'unexpected_error')
  end

  def reason_before_contact(lead)
    eligibility.consent_block_reason(lead) || (NO_CHANNEL unless channel?(lead))
  end

  # O telefone que o ContactConverter usaria (o WhatsApp confirmado ou o do Google) ou o e-mail achado no site.
  def channel?(lead)
    lead_payload.whatsapp(lead)[:whatsapp_phone].present? || lead.enriched_email.present?
  end

  def convert(lead)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user, consent_veto: eligibility.consent_veto).perform.contact
  end

  def row_for(contact)
    CampaignJourney::AudienceWriter::Row.new(
      contact_id: contact.id, name: contact.name, phone: ConversationAudience::Reach.phone(contact),
      email: ConversationAudience::Reach.email(contact), company_name: company_name(contact), extra_values: {}
    )
  end

  # A mesma leitura da mensagem para empresa_cliente.nome (TemplateFields::ContactResolver).
  def company_name(contact)
    contact.try(:company)&.name.presence || contact.additional_attributes.to_h['company_name'].to_s.squish.presence
  end

  def left(lead_id, reason_code)
    { lead_id: lead_id, reason_code: reason_code, message: I18n.t("autonomia.prospecting.audience.left_out.#{reason_code}") }
  end

  def leads_by_id
    @leads_by_id ||= @leads_scope.where(id: @lead_ids).index_by(&:id)
  end

  def eligibility
    @eligibility ||= Autonomia::Prospecting::SegmentEligibility.new(account: @account, user: @user)
  end

  def lead_payload
    @lead_payload ||= Autonomia::Prospecting::LeadPayload.new(account: @account)
  end

  def writer
    CampaignJourney::AudienceWriter.new(@account, user: @user, source: SOURCE)
  end
end
