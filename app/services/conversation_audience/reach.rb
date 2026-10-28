# Who of a search's people can receive (#2277), by the rule of a spreadsheet audience (CampaignImports::AudienceRowContacts):
# a phone OR an e-mail. The campaign then sends each person by the channel they have (WhatsApp and SMS need a valid
# mobile, e-mail a valid address), so an account that only sends e-mail gets its whole audience. Nobody who asked not
# to receive active messages counts. Those people never enter the list on the screen nor the saved audience; the screen
# only names them, by reason, at the end ("sem_contato", "nao_quer").
module ConversationAudience::Reach
  NO_CONTACT = 'sem_contato'.freeze
  OPTED_OUT = 'nao_quer'.freeze

  module_function

  # { contact_id => reason } for the contacts that cannot receive.
  def left_aside(contacts)
    contacts.each_with_object({}) do |contact, aside|
      reason = reason_for(contact)
      aside[contact.id] = reason if reason
    end
  end

  def reason_for(contact)
    return OPTED_OUT if contact.opted_out?

    NO_CONTACT if phone(contact).nil? && email(contact).nil?
  end

  # What the list shows of how the person is reached: the masked phone, or the masked e-mail when there is no phone.
  def masked(contact)
    phone(contact)&.masked || email(contact)&.masked
  end

  # The spreadsheet's reading first; a number stored without the 9th digit gets it added (the send matches the
  # contact's number with or without it, CampaignImports::ContactMatcher).
  def phone(contact)
    return if contact.phone_number.blank?

    normalize(contact.phone_number) || normalize(contact.phone_number, national_formats: true, legacy_mobiles: true)
  end

  def email(contact)
    return if contact.email.blank?

    EmailCampaigns::EmailNormalizer.normalize!(contact.email)
  rescue EmailCampaigns::EmailNormalizer::Error
    nil
  end

  def normalize(number, **)
    CampaignImports::PhoneNormalizer.normalize!(number, **)
  rescue CampaignImports::PhoneNormalizer::Error
    nil
  end
end
