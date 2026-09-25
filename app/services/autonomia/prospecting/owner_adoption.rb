# "Usar como contato" (#680, frente A): um dos sócios que a pesquisa do lead achou vira o decisor, e o contato do lead
# passa a ser essa pessoa (ContactConverter).
#
# - Só vale nome da lista que a tela mostra (Research::Payload): com a empresa achada, os donos da pesquisa do próprio
#   lead. Nome fora dela é recusado; ninguém vira decisor por digitação.
# - Estado e confiança do decisor seguem os da empresa, como na pesquisa: a certeza é a da identificação da empresa, e o
#   sócio vem do mesmo cadastro. Decisor novo solta as redes do anterior, como o LeadWriter.
# - A troca fica registrada no lead (metadata decision_adoption: quem, quando, nome anterior), como o Orth audita.
# - O resultado diz o que aconteceu com o contato, para a tela não afirmar uma troca que não houve: o contato virou a
#   pessoa (updated), é de outro lead com o mesmo telefone ou e-mail e ficou como estava (shared_with_other_lead), ou é
#   um contato do usuário, cujo nome não é nosso para trocar (kept_existing_contact).
# - Lead já no CRM: o card passa a mostrar o decisor novo (metadata e a linha "Decisor" da descrição).
class Autonomia::Prospecting::OwnerAdoption
  class NotAnOwner < StandardError; end

  Result = Struct.new(:contact_outcome, :shared_lead_name, keyword_init: true)

  FOUND = Autonomia::Prospecting::Research::Payload::FOUND

  def initialize(lead:, user:, owner_name:)
    @lead = lead
    @user = user
    @owner_name = Autonomia::Prospecting::Research::Normalization.squish(owner_name.to_s)
  end

  def perform
    result = Autonomia::Prospecting::Lead.transaction do
      @lead.lock!
      owner = find_owner
      raise NotAnOwner if owner.nil?

      previous_line = card_decision_line
      @lead.update!(decision_attributes(owner))
      contact = Autonomia::Prospecting::ContactConverter.new(lead: @lead, user: @user).perform.contact
      refresh_card!(previous_line)
      outcome(contact, owner)
    end
    ::Crm::Cards::Broadcaster.broadcast(@refreshed_card, ::Events::Types::CRM_CARD_UPDATED) if @refreshed_card
    result
  end

  private

  def find_owner
    return if @owner_name.nil?

    owners = Autonomia::Prospecting::Research::Payload.build(@lead)[:owners]
    owners.map(&:to_h).find { |owner| Autonomia::Prospecting::Research::Normalization.squish(owner['name'].to_s) == @owner_name }
  end

  def decision_attributes(owner)
    attributes = {
      decision_name: owner['name'], decision_role: owner['qualification'], decision_source_url: nil,
      decision_research_status: FOUND.include?(@lead.decision_research_status) ? @lead.decision_research_status : @lead.company_research_status,
      metadata: @lead.metadata.to_h.merge('decision_adoption' => adoption(owner))
    }
    return attributes if @lead.decision_name == owner['name']

    attributes.merge(decision_linkedin: nil, decision_instagram: nil)
  end

  def adoption(owner)
    { 'name' => owner['name'], 'previous_name' => @lead.decision_name, 'adopted_by_id' => @user&.id, 'adopted_at' => Time.current.iso8601 }
  end

  def outcome(contact, owner)
    return Result.new(contact_outcome: 'updated') if contact.name == owner['name']

    owner_lead_id = Autonomia::Prospecting::ContactConverter.owner_lead_id(contact)
    if owner_lead_id.present? && owner_lead_id != @lead.id
      shared = Autonomia::Prospecting::Lead.find_by(account_id: @lead.account_id, id: owner_lead_id)
      return Result.new(contact_outcome: 'shared_with_other_lead', shared_lead_name: shared&.name)
    end

    Result.new(contact_outcome: 'kept_existing_contact')
  end

  def card_decision_line
    card = @lead.crm_card
    card && card_converter(card).decision_snapshot['line']
  end

  def refresh_card!(previous_line)
    card = @lead.crm_card
    return if card.nil?

    snapshot = card_converter(card).decision_snapshot
    metadata = card.metadata.to_h
    prospecting = metadata['autonomia_prospecting'].to_h.merge('decision' => snapshot['decision'])
    card.update!(
      metadata: metadata.merge('autonomia_prospecting' => prospecting),
      description: replace_decision_line(card.description, previous_line, snapshot['line'])
    )
    @refreshed_card = card
  end

  # Troca só a linha do decisor que nós escrevemos; o resto da descrição (inclusive o que o usuário acrescentou) fica.
  def replace_decision_line(description, previous_line, new_line)
    lines = description.to_s.split("\n")
    return lines.filter_map { |line| line == previous_line ? new_line : line }.join("\n") if previous_line.present? && lines.include?(previous_line)
    return description if new_line.blank? || lines.include?(new_line)

    [*lines, new_line].join("\n")
  end

  def card_converter(card)
    Autonomia::Prospecting::CrmCardConverter.new(lead: @lead, user: @user, pipeline_id: card.pipeline_id, stage_id: card.stage_id)
  end
end
