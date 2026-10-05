require 'cgi'

# Campaign reply code (#1002, PRD §6.7, §8.3 and K4): the e-mail button that leads to WhatsApp
# carries the campaign's #CODE in the prefilled text, the same marker as a tracked link. When
# the person sends it, Ctwa::TrackedLinkAttributor (which already finds the code in the message)
# hands it here and the conversation gets the campaign mark.
#
# Codes share the tracked link alphabet and length and are unique against tracked link codes
# too, so one #CODE never means two things.
module CampaignJourney::ReplyCodes
  module_function

  CODE_LENGTH = 6

  # The campaign's code, created on first use. Safe under concurrent calls (unique index).
  def code_for!(campaign)
    existing = find_for(campaign)
    return existing.code if existing

    CampaignReplyCode.create!(account_id: campaign.account_id, campaign: campaign, code: generate_code).code
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    find_for(campaign)&.code || raise
  end

  # wa.me link of a WhatsApp inbox whose prefilled text ends with the campaign's #CODE. For the
  # e-mail builder's "talk on WhatsApp" button; nil when the inbox has no phone number.
  def wa_link(campaign, inbox:, text: '')
    phone = inbox&.channel.try(:phone_number).to_s.delete('+')
    return if phone.blank?

    message = [text.to_s.strip.presence, "##{code_for!(campaign)}"].compact.join(' ')
    "https://wa.me/#{phone}?text=#{CGI.escape(message)}"
  end

  # Called by Ctwa::TrackedLinkAttributor when a #CODE is not a tracked link of the inbox.
  def attribute!(conversation, code)
    return false unless CampaignJourney::Config.enabled?

    reply_code = CampaignReplyCode.find_by(account_id: conversation.account_id, code: code)
    campaign = reply_code&.campaign
    return false if campaign.blank?

    CampaignJourney::CampaignMarks.mark!(conversation, campaign)
  end

  def find_for(campaign)
    CampaignReplyCode.find_by(campaign_type: campaign.class.name, campaign_id: campaign.id)
  end

  def generate_code
    alphabet = Ctwa::TrackedLink::CODE_ALPHABET
    loop do
      code = Array.new(CODE_LENGTH) { alphabet[SecureRandom.random_number(alphabet.length)] }.join
      return code unless CampaignReplyCode.exists?(code: code) || Ctwa::TrackedLink.exists?(code: code)
    end
  end
end
