# "Usar como contato" (#680, frente A): um dos sócios que a pesquisa do lead achou vira o decisor, e o contato do lead
# passa a ser essa pessoa (ContactConverter).
#
# - Só vale nome da lista que a tela mostra (Research::Payload): com a empresa achada, os donos da pesquisa do próprio
#   lead. Nome fora dela é recusado; ninguém vira decisor por digitação.
# - Estado e confiança do decisor seguem os da empresa, como na pesquisa: a certeza é a da identificação da empresa, e o
#   sócio vem do mesmo cadastro. Decisor novo solta as redes do anterior, como o LeadWriter.
# - A troca fica registrada no lead (metadata decision_adoption: quem, quando, nome anterior), como o Orth audita.
class Autonomia::Prospecting::OwnerAdoption
  class NotAnOwner < StandardError; end

  FOUND = Autonomia::Prospecting::Research::Payload::FOUND

  def initialize(lead:, user:, owner_name:)
    @lead = lead
    @user = user
    @owner_name = Autonomia::Prospecting::Research::Normalization.squish(owner_name.to_s)
  end

  def perform
    Autonomia::Prospecting::Lead.transaction do
      @lead.lock!
      owner = find_owner
      raise NotAnOwner if owner.nil?

      @lead.update!(decision_attributes(owner))
      Autonomia::Prospecting::ContactConverter.new(lead: @lead, user: @user).perform
    end
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
end
