# "Suas listas" da Prospecção nova (#2775, F6): as listas são os Públicos de Campanhas que a Prospecção criou
# (CampaignImport do fluxo audience, options['source'] = 'prospecting', AudienceFromLeads). Este serviço só lê: quais
# são, os números de cada uma, as empresas de uma lista e em quais listas um contato está. Pôr e tirar ficam no
# CampaignJourney::AudienceMembership.
# Não há número de "já chamadas": a Prospecção não grava a chamada, e o número que se aproximava disso confundia
# (decisão da revisão do #2775).
#
# Os números (só as linhas imported contam; a tirada fica como removed e não entra):
# - companies: as pessoas da lista (contatos distintos);
# - whatsapp / email: os canais recontados do Público (channels.count), a mesma régua que o envio usa
#   (CampaignJourney::AudienceContacts);
# - in_crm: contatos da lista com algum card no funil da conta (Crm::Card.contact_id);
# - locked: a lista já foi usada em campanha que saiu (CampaignJourney::AudienceUsage) e não muda mais.
class Autonomia::Prospecting::AudienceLists
  SOURCE = Autonomia::Prospecting::AudienceFromLeads::SOURCE
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

  # { id => { companies:, whatsapp:, email:, in_crm:, locked: } }, com uma consulta por número.
  def numbers(audiences)
    ids = audiences.map(&:id)
    counts = {
      companies: count_by_audience(active_rows(ids)),
      in_crm: count_by_audience(active_rows(ids).where(contact_id: crm_contact_ids)),
      locked: CampaignJourney::AudienceUsage.locked_ids(audiences)
    }
    audiences.to_h { |audience| [audience.id, numbers_of(audience, counts)] }
  end

  # { id => [lead_ids] }: quais dos leads (os que quem pede vê, leads_scope) já estão em cada lista, pelo contato do lead
  # (linha imported). O lead sem contato ainda não está em lista nenhuma. Duas consultas, para a página inteira.
  def lead_ids_in(audiences, lead_ids, leads_scope:)
    result = audiences.to_h { |audience| [audience.id, []] }
    return result if lead_ids.empty?

    leads_by_contact = leads_scope.where(id: lead_ids).where.not(contact_id: nil).pluck(:contact_id, :id).group_by(&:first)
    rows_of_contacts(audiences, leads_by_contact.keys).each do |audience_id, contact_id|
      result[audience_id].concat(leads_by_contact[contact_id].map(&:last))
    end
    result.transform_values(&:sort)
  end

  # As listas em que o contato está (linha imported), para a gaveta da empresa.
  def containing(contact_id)
    return scope.none if contact_id.nil?

    scope.where(id: CampaignImportRow.status_imported.where(contact_id: contact_id).select(:campaign_import_id))
  end

  # Uma página das empresas da lista, na ordem em que entraram (row_number), a partir de depois da linha `after`
  # (cursor): tirar alguém no meio não faz a próxima página pular ninguém, como faria um offset. next_after: a linha da
  # última empresa da página, ou nil quando não há mais. lead_id: o lead que quem pede vê (leads_scope) ligado ao
  # contato, para a tela abrir a gaveta e tirar pelo lead; nil quando não vê nenhum.
  def members(audience, after:, leads_scope:)
    rows = active_rows([audience.id])
    page_rows = rows.where('campaign_import_rows.row_number > ?', after.to_i).includes(:contact).order(:row_number)
                    .limit(MEMBERS_PER_PAGE + 1).to_a
    more = page_rows.size > MEMBERS_PER_PAGE
    page_rows = page_rows.first(MEMBERS_PER_PAGE)
    flags = member_flags(page_rows.map(&:contact_id), leads_scope)
    { members: page_rows.map { |row| member(row, flags) }, total: rows.count, next_after: (page_rows.last&.row_number if more) }
  end

  private

  def numbers_of(audience, counts)
    channels = audience.channels.to_h
    {
      companies: counts[:companies][audience.id].to_i, whatsapp: channels.dig('whatsapp', 'count').to_i,
      email: channels.dig('email', 'count').to_i, in_crm: counts[:in_crm][audience.id].to_i,
      locked: counts[:locked].include?(audience.id)
    }
  end

  def active_rows(ids)
    CampaignImportRow.status_imported.where(campaign_import_id: ids).where.not(contact_id: nil)
  end

  # [[audience_id, contact_id]] das linhas imported desses contatos nessas listas.
  def rows_of_contacts(audiences, contact_ids)
    active_rows(audiences.map(&:id)).where(contact_id: contact_ids).distinct.pluck(:campaign_import_id, :contact_id)
  end

  def count_by_audience(rows)
    rows.group(:campaign_import_id).distinct.count(:contact_id)
  end

  def crm_contact_ids
    Crm::Card.where(account_id: @account.id).where.not(contact_id: nil).select(:contact_id)
  end

  def member_flags(contact_ids, leads_scope)
    {
      in_crm: Crm::Card.where(account_id: @account.id, contact_id: contact_ids).distinct.pluck(:contact_id).to_set,
      lead_ids: leads_scope.where(contact_id: contact_ids).group(:contact_id).minimum(:id)
    }
  end

  def member(row, flags)
    {
      contact_id: row.contact_id, row_number: row.row_number, name: row.contact&.name.presence || row.normalized_name,
      company_name: row.company_name, whatsapp: row.normalized_phone_hash.present?, email: row.normalized_email_hash.present?,
      in_crm: flags[:in_crm].include?(row.contact_id), lead_id: flags[:lead_ids][row.contact_id]
    }
  end
end
