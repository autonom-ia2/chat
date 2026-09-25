# Quem pediu para não receber mensagem é a pessoa do outro lado do número, não o lead (#680). Um lead em no_consent
# veta a campanha para qualquer outro lead da conta que chegue ao mesmo contato: o contato ligado a ele, o mesmo
# telefone ou WhatsApp (E.164) ou o mesmo e-mail. Assim a guarda da campanha não deixa a mensagem chegar a quem recusou
# por um segundo lead do mesmo número (central única, franquia, outra unidade).
class Autonomia::Prospecting::ConsentVeto
  def initialize(account:)
    @account = account
  end

  def vetoed?(lead:, contact:)
    return true if contact.present? && refused_contact_ids.include?(contact.id)

    phones = phones_of(lead) + [contact&.phone_number].compact
    emails = [email_of(lead), contact&.email&.downcase].compact
    refused_phones.intersect?(phones.to_set) || refused_emails.intersect?(emails.to_set)
  end

  private

  def refused_leads
    @refused_leads ||= Autonomia::Prospecting::Lead.where(account: @account, status: :no_consent).to_a
  end

  def refused_contact_ids
    @refused_contact_ids ||= refused_leads.filter_map(&:contact_id).to_set
  end

  def refused_phones
    @refused_phones ||= (refused_leads.flat_map { |lead| phones_of(lead) } + refused_contacts.filter_map(&:phone_number)).to_set
  end

  def refused_emails
    @refused_emails ||= (
      refused_leads.filter_map { |lead| email_of(lead) } + refused_contacts.filter_map { |contact| contact.email&.downcase }
    ).to_set
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
