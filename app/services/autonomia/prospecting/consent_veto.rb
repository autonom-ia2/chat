# Quem pediu para não receber mensagem é a pessoa do outro lado do número, não o lead (#680). Um lead recusado
# (consent_refused_at, com qualquer status, ou o status no_consent; chat#713) veta a campanha para qualquer outro lead da
# conta que chegue ao mesmo contato: o contato ligado a ele, o mesmo telefone ou WhatsApp (E.164) ou o mesmo e-mail.
# Assim a guarda da campanha não deixa a mensagem chegar a quem recusou por um segundo lead do mesmo número (central
# única, franquia, outra unidade).
class Autonomia::Prospecting::ConsentVeto
  def initialize(account:)
    @account = account
  end

  def vetoed?(lead:, contact:)
    return true if contact.present? && contact_vetoed?(contact)

    refused_phones.intersect?(phones_of(lead).to_set) || refused_emails.include?(email_of(lead))
  end

  # O contato sozinho, sem lead: é o de um lead recusado, ou tem o telefone ou o e-mail de um. Decide se a recusa da
  # Prospecção gravada no contato (ContactOptOutSync) ainda tem quem a sustente.
  # Os conjuntos de recusa não guardam telefone nem e-mail em branco: dois contatos sem telefone não são a mesma pessoa.
  def contact_vetoed?(contact)
    refused_contact_ids.include?(contact.id) ||
      refused_phones.include?(contact.phone_number) ||
      refused_emails.include?(contact.email&.downcase)
  end

  # Os contatos da conta que a recusa deste lead veta: o ligado a ele, os do mesmo telefone ou WhatsApp (os números de
  # phones_of) e o do mesmo e-mail. É a mesma conta de vetoed?, olhada do lado de quem recusou.
  def contacts_vetoed_by(lead)
    email = email_of(lead)
    contacts = @account.contacts
    scope = contacts.where(id: lead.contact_id).or(contacts.where(phone_number: phones_of(lead)))
    scope = scope.or(contacts.where('LOWER(contacts.email) = ?', email)) if email
    scope.to_a
  end

  private

  def refused_leads
    @refused_leads ||= Autonomia::Prospecting::Lead.where(account: @account).consent_refused.to_a
  end

  def refused_contact_ids
    @refused_contact_ids ||= refused_leads.filter_map(&:contact_id).to_set
  end

  def refused_phones
    @refused_phones ||= (refused_leads.flat_map { |lead| phones_of(lead) } + refused_contacts.map(&:phone_number)).compact_blank.to_set
  end

  def refused_emails
    @refused_emails ||= (
      refused_leads.filter_map { |lead| email_of(lead) } + refused_contacts.map { |contact| contact.email.to_s.downcase }
    ).compact_blank.to_set
  end

  def refused_contacts
    @refused_contacts ||= @account.contacts.where(id: refused_contact_ids.to_a).to_a
  end

  # Os números pelos quais o ContactConverter chegaria a um contato: o do Google, o WhatsApp verificado e o do site.
  def phones_of(lead)
    whatsapp = payload_builder.whatsapp(lead)
    [lead.phone, whatsapp[:whatsapp_phone], lead.enriched_whatsapp].filter_map { |raw| e164(raw) }.uniq
  end

  def email_of(lead)
    lead.enriched_email.to_s.strip.downcase.presence
  end

  def e164(raw)
    return if raw.blank?

    Autonomia::Prospecting::PhoneContract.e164(raw, region: region)
  end

  def region
    @region ||= Autonomia::Prospecting::PhoneContract.region_for(@account)
  end

  def payload_builder
    @payload_builder ||= Autonomia::Prospecting::LeadPayload.new(account: @account)
  end
end
