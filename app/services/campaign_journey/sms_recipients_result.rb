# SMS result (#1007): the same campaign_recipients as WhatsApp Oficial, without "Lidas".
class CampaignJourney::SmsRecipientsResult < CampaignJourney::CampaignRecipientsResult
  FILTERS = CampaignJourney::CampaignRecipientsResult::SMS_FILTERS

  def channel
    CampaignJourney::ResultFinder::SMS
  end
end
