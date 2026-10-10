require 'digest'

# The phone and email of one audience row (Públicos #992, Importar contatos #1006), read with the
# account's CampaignImports::ContactReading. A row needs a valid phone or a valid email; when it has
# neither, errors says why (or that both are missing). Raw values never leave masked.
class CampaignImports::AudienceRowContacts
  def initialize(reading)
    @reading = reading
  end

  def fields(phone, email)
    phone_result, phone_error = normalize(phone) { |value| @reading.phone(value) }
    email_result, email_error = normalize(email) { |value| @reading.email(value) }
    reasons = [phone_error, email_error].compact.presence || ['missing_contact']
    phone_fields(phone, phone_result).merge(email_fields(email, email_result), errors: phone_result || email_result ? [] : reasons)
  end

  private

  def phone_fields(raw, result)
    {
      raw_phone_masked: result&.masked || CampaignImports::PhoneNormalizer.mask_raw(raw),
      normalized_phone: result&.phone_number, normalized_phone_hash: result&.hash,
      ninth_digit_added: result&.ninth_digit_added == true
    }
  end

  def email_fields(raw, result)
    { email: result&.email, email_hash: result && Digest::SHA256.hexdigest(result.email),
      email_masked: raw.present? ? masked_email(raw, result) : nil }
  end

  # customer_base: every address of the cell is masked, not only the first ("ana@x.com; ana@y.com").
  def masked_email(raw, result)
    return EmailCampaigns::EmailNormalizer.mask(raw.downcase) unless @reading.customer_base?

    result ? EmailCampaigns::EmailNormalizer.mask(result.email) : CampaignImports::CellValues.masked_emails(raw)
  end

  def normalize(value)
    return [nil, nil] if value.blank?

    [yield(value), nil]
  rescue CampaignImports::PhoneNormalizer::Error, EmailCampaigns::EmailNormalizer::Error => e
    [nil, e.message]
  end
end
