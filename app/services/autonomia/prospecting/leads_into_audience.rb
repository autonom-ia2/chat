# Acrescentar leads a uma lista da Prospecção nova que já existe (#2775, F6). O mesmo caminho do "Guardar lista"
# (AudienceFromLeads: a mesma conversão em contato, o mesmo teto e o mesmo left_out); muda só o destino:
# - a lista já usada em campanha que saiu é recusada antes de criar qualquer contato (audience_locked,
#   CampaignJourney::AudienceUsage), e de novo, dentro da trava, pelo AudienceMembership;
# - quem já está na lista (linha imported) sai com already_in_list; quem tinha sido tirado volta na mesma linha;
# - as linhas são gravadas pelo CampaignJourney::AudienceMembership; a recusa dele vira Error com o mesmo código e
#   contacts_saved (os contatos já criados ficam), como a do writer.
class Autonomia::Prospecting::LeadsIntoAudience < Autonomia::Prospecting::AudienceFromLeads
  def initialize(account:, user:, lead_ids:, audience:, leads_scope: nil)
    super(account: account, user: user, lead_ids: lead_ids, name: audience.name, leads_scope: leads_scope)
    @audience = audience
  end

  private

  def check_target!
    raise Error, CampaignJourney::AudienceMembership::LOCKED if CampaignJourney::AudienceUsage.locked?(@audience)
  end

  def members
    @members ||= @audience.campaign_import_rows.status_imported.where.not(contact_id: nil).pluck(:contact_id).to_set
  end

  def write(rows, left_out)
    CampaignJourney::AudienceMembership.add(@audience, rows.values).audience
  rescue CampaignJourney::AudienceMembership::Error => e
    raise Error.new(e.message, left_out: left_out, contacts_saved: true)
  end
end
