# Whether a spreadsheet cell holds something we can reach a person through. Reuses the
# existing normalizers (Brazilian mobile, email) so every importer agrees on what is valid; a cell
# with several values counts when one of them is valid (CampaignImports::CellValues).
module CampaignImports::ContactValues
  module_function

  def readable?(value)
    value.valid_encoding? && value.exclude?("\0")
  end

  def phone?(value)
    text = value.to_s.strip
    return false if text.empty? || !readable?(text)

    CampaignImports::CellValues.normalize!(CampaignImports::PhoneNormalizer, text)
    true
  rescue CampaignImports::PhoneNormalizer::Error
    false
  end

  def email?(value)
    text = value.to_s.strip
    return false if text.empty? || !readable?(text)

    CampaignImports::CellValues.normalize!(EmailCampaigns::EmailNormalizer, text)
    true
  rescue EmailCampaigns::EmailNormalizer::Error
    false
  end

  def contact?(value)
    phone?(value) || email?(value)
  end
end
