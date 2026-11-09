# Mudanças numa lista da Prospecção nova que não vêm de leads (#2775, F6): devolver quem foi tirado (o "Desfazer" do
# "Tirar") e criar uma cópia para editar (a lista já enviada não muda; a cópia nasce nova, sem campanha).
#
# Nos dois, a linha de cada contato é lida de novo do contato (AudienceRows.row_for): o telefone e o e-mail de agora,
# com a régua de todo Público (ConversationAudience::Reach): quem pediu para não receber ou ficou sem telefone e sem
# e-mail desde então fica de fora (skipped_contact_ids).
class Autonomia::Prospecting::AudienceListChanges
  Copy = Struct.new(:audience, :skipped_contact_ids, keyword_init: true)

  def initialize(account:, user:)
    @account = account
    @user = user
  end

  # Volta à lista só quem foi tirado dela (linha removed); outro contato não entra por aqui.
  def restore(audience, contact_ids)
    removed = audience.campaign_import_rows.status_removed.where(contact_id: Array(contact_ids)).distinct.pluck(:contact_id)
    rows, skipped = reachable_rows(removed)
    raise CampaignJourney::AudienceMembership::Error, 'no_rows' if rows.empty?

    result = CampaignJourney::AudienceMembership.add(audience, rows)
    result.skipped_contact_ids.concat(skipped)
    result
  end

  # Um Público novo da Prospecção com quem está na lista hoje, na mesma ordem, e o nome "<nome> (cópia)".
  def copy(audience)
    contact_ids = audience.campaign_import_rows.status_imported.where.not(contact_id: nil).order(:row_number).pluck(:contact_id).uniq
    rows, skipped = reachable_rows(contact_ids)
    raise CampaignJourney::AudienceWriter::Error, 'no_rows' if rows.empty?

    name = I18n.t('autonomia.prospecting.audience.copy_name', name: audience.name)
    Copy.new(audience: writer.perform(name, rows), skipped_contact_ids: skipped)
  end

  private

  # [linhas de quem pode receber, na ordem dada; ids de quem ficou de fora].
  def reachable_rows(contact_ids)
    contacts = @account.contacts.where(id: contact_ids).index_by(&:id)
    reachable, skipped = contact_ids.partition do |id|
      contacts[id] && ConversationAudience::Reach.reason_for(contacts[id]).nil?
    end
    [reachable.map { |id| Autonomia::Prospecting::AudienceRows.row_for(contacts[id]) }, skipped]
  end

  def writer
    CampaignJourney::AudienceWriter.new(@account, user: @user, source: Autonomia::Prospecting::AudienceFromLeads::SOURCE)
  end
end
