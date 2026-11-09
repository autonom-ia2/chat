# Acrescentar leads a uma lista da Prospecção nova que já existe (#2775, F6). O mesmo caminho do "Guardar lista"
# (AudienceFromLeads: a mesma conversão em contato, o mesmo teto e o mesmo left_out); muda só o destino:
# - a lista já usada em campanha que saiu é recusada antes de criar qualquer contato (audience_locked,
#   CampaignJourney::AudienceUsage), e de novo, dentro da trava, pelo AudienceMembership;
# - quem já está na lista (linha imported) sai com already_in_list; quem tinha sido tirado volta na mesma linha. Vale
#   também para quem entrou na lista entre a leitura de members e a trava (outra aba, outra pessoa): o
#   AudienceMembership pula esse contato (skipped_contact_ids), e o lead sai de entered_lead_ids para left_out;
# - quando todos os que ficaram de fora já estavam na lista, a recusa é all_already_in_list ("Essas empresas já
#   estavam nesta lista."), e não no_rows, que fala de quem não pode receber;
# - as linhas são gravadas pelo CampaignJourney::AudienceMembership; a recusa dele vira Error com o mesmo código e
#   contacts_saved (os contatos já criados ficam), como a do writer;
# - channels_off: os canais desligados da lista que ganharam gente, para a tela avisar na hora.
class Autonomia::Prospecting::LeadsIntoAudience < Autonomia::Prospecting::AudienceFromLeads
  ALREADY_IN_LIST = 'already_in_list'.freeze
  ALL_ALREADY_IN_LIST = 'all_already_in_list'.freeze

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

  def no_rows_code(left_out)
    left_out.all? { |item| item[:reason_code] == ALREADY_IN_LIST } ? ALL_ALREADY_IN_LIST : super
  end

  def finish(rows, left_out)
    result = add(rows, left_out)
    skipped = result.skipped_contact_ids.to_set
    entered, already = rows.partition { |_lead_id, row| skipped.exclude?(row.contact_id) }
    left_out += already.map { |lead_id, _row| left(lead_id, ALREADY_IN_LIST) }
    raise Error.new(no_rows_code(left_out), left_out: left_out, contacts_saved: true) if entered.empty?

    Result.new(audience: result.audience, entered_lead_ids: entered.map(&:first), left_out: left_out,
               channels_off: result.channels_off)
  end

  def add(rows, left_out)
    CampaignJourney::AudienceMembership.add(@audience, rows.values)
  rescue CampaignJourney::AudienceMembership::Error => e
    raise Error.new(e.message, left_out: left_out, contacts_saved: true)
  end
end
