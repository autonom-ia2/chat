# "Suas listas" da Prospecção nova (#2775, F6): as listas são os Públicos de Campanhas que a Prospecção criou
# (CampaignImport do fluxo audience, options['source'] = 'prospecting', AudienceFromLeads). Este serviço só lê: quais
# são, os números de cada uma, as empresas de uma lista e em quais listas um contato está. Pôr e tirar ficam no
# CampaignJourney::AudienceMembership.
#
# Os números (só as linhas imported contam; a tirada fica como removed e não entra):
# - companies: as pessoas da lista (contatos distintos);
# - whatsapp / email: os canais recontados do Público (channels.count), a mesma régua que o envio usa
#   (CampaignJourney::AudienceContacts);
# - in_crm: contatos da lista com algum card no funil da conta (Crm::Card.contact_id);
# - called: contatos da lista que já foram chamados pela Prospecção. A régua é a da fila "Para chamar" (F5,
#   ParaChamar): a empresa sai da fila quando é tratada. "Já chamada" é o lead da conta ligado ao contato que foi
#   para o funil (crm_card_id) ou foi qualificado (qualified ou ready_for_campaign). O descartado e o que recusou também
#   saem da fila, mas não foram chamados ("Não serve"), e o adiado ("Depois") volta no dia seguinte: nenhum dos dois conta;
# - locked: a lista já foi usada em campanha que saiu (CampaignJourney::AudienceUsage) e não muda mais.
class Autonomia::Prospecting::AudienceLists
  SOURCE = Autonomia::Prospecting::AudienceFromLeads::SOURCE
  CALLED_STATUSES = %w[qualified ready_for_campaign].freeze
  MEMBERS_PER_PAGE = 25

  def initialize(account)
    @account = account
  end

  # Os Públicos da Prospecção desta conta, prontos (o writer grava completed), do mais novo ao mais velho.
  def scope
    @account.campaign_imports.where(status: :completed)
            .where("campaign_imports.options->>'flow' = ? AND campaign_imports.options->>'source' = ?", CampaignImport::AUDIENCE_FLOW, SOURCE)
            .order(created_at: :desc, id: :desc)
  end

  # { id => { companies:, whatsapp:, email:, in_crm:, called:, locked: } }, com uma consulta por número.
  def numbers(audiences)
    ids = audiences.map(&:id)
    counts = {
      companies: count_by_audience(active_rows(ids)),
      in_crm: count_by_audience(active_rows(ids).where(contact_id: crm_contact_ids)),
      called: count_by_audience(active_rows(ids).where(contact_id: called_contact_ids)),
      locked: CampaignJourney::AudienceUsage.locked_ids(audiences)
    }
    audiences.to_h { |audience| [audience.id, numbers_of(audience, counts)] }
  end

  # As listas em que o contato está (linha imported), para a gaveta da empresa.
  def containing(contact_id)
    return scope.none if contact_id.nil?

    scope.where(id: CampaignImportRow.status_imported.where(contact_id: contact_id).select(:campaign_import_id))
  end

  # Uma página das empresas da lista, na ordem em que entraram (row_number). lead_id: o lead que quem pede vê
  # (leads_scope) ligado ao contato, para a tela abrir a gaveta e tirar pelo lead; nil quando não vê nenhum.
  def members(audience, page:, leads_scope:)
    rows = active_rows([audience.id]).includes(:contact).order(:row_number)
    page_rows = rows.offset((page - 1) * MEMBERS_PER_PAGE).limit(MEMBERS_PER_PAGE).to_a
    contact_ids = page_rows.map(&:contact_id)
    flags = member_flags(contact_ids, leads_scope)
    { members: page_rows.map { |row| member(row, flags) }, total: rows.count }
  end

  private

  def numbers_of(audience, counts)
    channels = audience.channels.to_h
    {
      companies: counts[:companies][audience.id].to_i, whatsapp: channels.dig('whatsapp', 'count').to_i,
      email: channels.dig('email', 'count').to_i, in_crm: counts[:in_crm][audience.id].to_i,
      called: counts[:called][audience.id].to_i, locked: counts[:locked].include?(audience.id)
    }
  end

  def active_rows(ids)
    CampaignImportRow.status_imported.where(campaign_import_id: ids).where.not(contact_id: nil)
  end

  def count_by_audience(rows)
    rows.group(:campaign_import_id).distinct.count(:contact_id)
  end

  def crm_contact_ids
    Crm::Card.where(account_id: @account.id).where.not(contact_id: nil).select(:contact_id)
  end

  def called_leads
    leads = Autonomia::Prospecting::Lead.where(account_id: @account.id).where.not(contact_id: nil)
    leads.where.not(crm_card_id: nil).or(leads.where(status: CALLED_STATUSES))
  end

  def called_contact_ids
    called_leads.select(:contact_id)
  end

  def member_flags(contact_ids, leads_scope)
    {
      in_crm: Crm::Card.where(account_id: @account.id, contact_id: contact_ids).distinct.pluck(:contact_id).to_set,
      called: called_leads.where(contact_id: contact_ids).distinct.pluck(:contact_id).to_set,
      lead_ids: leads_scope.where(contact_id: contact_ids).group(:contact_id).minimum(:id)
    }
  end

  def member(row, flags)
    {
      contact_id: row.contact_id, row_number: row.row_number, name: row.contact&.name.presence || row.normalized_name,
      company_name: row.company_name, whatsapp: row.normalized_phone_hash.present?, email: row.normalized_email_hash.present?,
      in_crm: flags[:in_crm].include?(row.contact_id), called: flags[:called].include?(row.contact_id),
      lead_id: flags[:lead_ids][row.contact_id]
    }
  end
end
