# Brazilian mobiles may be stored with or without the ninth digit. The exact number
# wins; otherwise the first stored variant is reused instead of creating a duplicate.
class CampaignImports::ContactMatcher
  def initialize(account)
    @account = account
    @normalizer = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new
  end

  def find(phone_number)
    numbers = candidates(phone_number)
    contacts = @account.contacts.where(phone_number: numbers).to_a
    numbers.each do |candidate|
      match = contacts.find { |contact| contact.phone_number == candidate }
      return match if match
    end
    nil
  end

  # The stored numbers that count as this phone, in the order #find tries them.
  def candidates(phone_number)
    variants = @normalizer.contact_candidates(phone_number.delete_prefix('+'))
    ([phone_number] + variants.map { |variant| "+#{variant}" }).uniq
  end
end
