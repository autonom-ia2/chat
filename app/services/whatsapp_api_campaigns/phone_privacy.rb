module WhatsappApiCampaigns
  module PhonePrivacy
    module_function

    # Same mask as audience rows and error CSVs (CampaignImports::PhoneMask, #993).
    def mask(phone_number)
      CampaignImports::PhoneMask.mask(phone_number)
    end

    def hash(phone_number)
      return if phone_number.blank?

      OpenSSL::Digest::SHA256.hexdigest(phone_number.to_s)
    end
  end
end
