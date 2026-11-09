# A linha de Público de um contato da Prospecção (#2695, #2775): o mesmo Row que o CampaignJourney::AudienceWriter e o
# CampaignJourney::AudienceMembership gravam, com o telefone e o e-mail lidos agora do contato (a prova de consentimento
# que o envio confere de novo) e o nome da empresa como a mensagem o lê. Usado ao guardar, acrescentar, devolver quem
# foi tirado e copiar uma lista.
module Autonomia::Prospecting::AudienceRows
  module_function

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
end
