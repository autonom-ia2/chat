# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): os leads escolhidos viram um Público de Campanhas
# (CampaignImport do fluxo audience, source 'prospecting'), gravado pelo CampaignJourney::AudienceWriter, o mesmo do
# Público por conversa. Substitui o segmento por etiqueta da Prospecção, que saiu (#2695).
#
# - Contato e empresa saem do ContactConverter (que chama o CompanyUpserter), um lead por vez e cada um na própria
#   transação, como o "Criar contatos" (ContactBatch): com decisor, o contato é a pessoa; sem decisor, a empresa, com o
#   mesmo nome; o contato fica ligado à empresa.
# - Fica de fora, com o motivo e sem gravar contato: lead que não existe ou que a pessoa não vê (not_found), o
#   descartado, o que recusou ou cujo contato recusou ou está bloqueado (SegmentEligibility#consent_block_reason), e
#   quem não teria telefone nem e-mail no contato (no_channel, pela mesma regra do conversor: ContactConverter#channel?).
# - Depois do contato vale a régua de todo Público (ConversationAudience::Reach): telefone OU e-mail do contato, e
#   nunca quem pediu para não receber. O contato que ainda assim fica sem canal (o telefone já era de outro contato)
#   sai com no_channel; ele continua criado, como no "Criar contatos".
# - Dois leads que dão no mesmo contato (a mesma pessoa em duas empresas) entram uma vez: o primeiro, na ordem do
#   pedido; o outro sai com same_contact.
# - O Público é gravado de uma vez, no fim. Recusa do writer (contato apagado no meio, por exemplo) vira Error com o
#   mesmo código e contacts_saved: os contatos já criados ficam.
class Autonomia::Prospecting::AudienceFromLeads
  # Teto do pedido, síncrono: no ambiente de teste (#2695 r1), 100 leads levaram 4,2 s e 200 levaram 7,7 s (~43 ms por
  # lead). O front (LIMITE_DO_PUBLICO) usa o mesmo número.
  MAX_LEADS = 100
  SOURCE = 'prospecting'.freeze
  NO_CHANNEL = 'no_channel'.freeze
  REACH_REASONS = {
    ConversationAudience::Reach::OPTED_OUT => 'opt_out',
    ConversationAudience::Reach::NO_CONTACT => NO_CHANNEL
  }.freeze

  Result = Struct.new(:audience, :entered_lead_ids, :left_out, keyword_init: true)

  # Recusa do pedido inteiro. left_out: quem ficou de fora e por quê, para a tela explicar mesmo quando ninguém entra.
  # contacts_saved: a recusa veio depois de criar os contatos (eles ficam gravados).
  class Error < StandardError
    attr_reader :left_out, :contacts_saved

    def initialize(message, left_out: [], contacts_saved: false)
      super(message)
      @left_out = left_out
      @contacts_saved = contacts_saved
    end
  end

  # leads_scope: os leads que quem pede enxerga (Visibility, #732 item 6). O controller sempre passa; sem ele, a conta.
  def initialize(account:, user:, lead_ids:, name:, leads_scope: nil)
    @account = account
    @user = user
    @leads_scope = leads_scope || Autonomia::Prospecting::Lead.where(account: account)
    @lead_ids = Array(lead_ids).filter_map { |value| lead_id(value) }.uniq
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

    Result.new(audience: write(rows, left_out), entered_lead_ids: rows.keys, left_out: left_out)
  end

  private

  # Só inteiro ou texto de dígitos (base 10) vale como id; o resto (lista, objeto, booleano, "0x1A") é ignorado.
  def lead_id(value)
    id = case value
         when Integer then value
         when String then Integer(value, 10, exception: false)
         end
    id if id&.positive?
  end

  def write(rows, left_out)
    writer.perform(@name, rows.values)
  rescue CampaignJourney::AudienceWriter::Error => e
    raise Error.new(e.message, left_out: left_out, contacts_saved: true)
  end

  # Põe o lead nas linhas do Público ou em left_out, com o motivo. Mesmo padrão de falha do ContactBatch: dado recusado
  # pelo modelo vira invalid_data; qualquer outra falha do lead vai para o tracker e vira unexpected_error, sem derrubar
  # os outros leads do pedido (o conversor não tem erro de domínio próprio).
  def place(lead_id, rows, left_out)
    lead = leads_by_id[lead_id]
    return left_out << left(lead_id, 'not_found') if lead.nil?

    converter = converter_for(lead)
    reason = eligibility.consent_block_reason(lead) || (NO_CHANNEL unless converter.channel?)
    return left_out << left(lead_id, reason) if reason

    add_row(lead_id, converter.perform.contact, rows, left_out)
  rescue ActiveRecord::RecordInvalid
    left_out << left(lead_id, 'invalid_data')
  rescue StandardError => e
    Rails.logger.error("[prospecting.audience_from_leads] lead=#{lead_id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: @account).capture_exception
    left_out << left(lead_id, 'unexpected_error')
  end

  def add_row(lead_id, contact, rows, left_out)
    reason = REACH_REASONS[ConversationAudience::Reach.reason_for(contact)]
    reason ||= 'same_contact' if rows.each_value.any? { |row| row.contact_id == contact.id }
    return left_out << left(lead_id, reason) if reason

    rows[lead_id] = row_for(contact)
  end

  def converter_for(lead)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: @user, consent_veto: eligibility.consent_veto)
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

  # O que o conversor e a régua leem de cada lead, numa consulta por associação.
  def leads_by_id
    @leads_by_id ||= @leads_scope.where(id: @lead_ids).includes(:account, :contact).index_by(&:id)
  end

  def eligibility
    @eligibility ||= Autonomia::Prospecting::SegmentEligibility.new(account: @account, user: @user)
  end

  def writer
    CampaignJourney::AudienceWriter.new(@account, user: @user, source: SOURCE)
  end
end
