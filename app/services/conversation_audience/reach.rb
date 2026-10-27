# Who of a search's people can receive (#2277), by the same consent rule as a spreadsheet audience
# (CampaignJourney::AudienceContacts): WhatsApp needs a valid Brazilian mobile, and nobody who asked not to receive
# active messages counts. Those people never enter the list on the screen nor the saved audience; the screen only
# names them, by reason, at the end ("sem_whatsapp", "nao_quer").
module ConversationAudience::Reach
  NO_WHATSAPP = 'sem_whatsapp'.freeze
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

    NO_WHATSAPP if phone(contact).nil?
  end

  # The spreadsheet's reading first; a number stored without the 9th digit gets it added (the send matches the
  # contact's number with or without it, CampaignImports::ContactMatcher).
  def phone(contact)
    return if contact.phone_number.blank?

    normalize(contact.phone_number) || normalize(contact.phone_number, national_formats: true, legacy_mobiles: true)
  end

  def normalize(number, **)
    CampaignImports::PhoneNormalizer.normalize!(number, **)
  rescue CampaignImports::PhoneNormalizer::Error
    nil
  end
end
