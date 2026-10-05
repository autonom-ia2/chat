# WhatsApp API campaigns of the journey (#999, PRD §8.3 and §8.6; acceptance N2, D7).
# Prepended by config/initializers/campaign_journey.rb; the engine (WhatsappApiCampaigns::*)
# keeps its behaviour for campaigns without an audience link.
module CampaignJourney::WhatsappApiAudience
  MISSING_COMPANY_REASON = 'falta empresa'.freeze

  def self.company_default(campaign)
    link = CampaignAudienceLink.for_campaign(campaign)
    link&.variable_defaults.to_h[WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE].presence
  end

  # WhatsappApiCampaigns::AudienceResolver: a linked campaign resolves the audience's contacts
  # (same eligibility as WhatsApp Oficial, CampaignJourney::AudienceContacts) instead of labels.
  module Resolver
    private

    def contacts
      link = CampaignAudienceLink.for_campaign(@campaign)
      return super unless link

      CampaignJourney::AudienceContacts.contacts_for(link, channel: :whatsapp)
    end

    # Fails closed: the audience WhatsApp channel turned off → everyone skipped with the reason.
    # D7: a message with {{contact.company}} skips the person without a company ("falta empresa"),
    # unless the campaign has a default text. Skipped = cancelled with the reason (like opted_out).
    def apply_recipient_validation_status(recipient, contact, duplicate_phone)
      super
      return unless recipient.pending?

      reason = skip_reason(contact)
      return unless reason

      recipient.status = :cancelled
      recipient.last_error_message = reason
      recipient.cancelled_at = Time.current
    end

    def skip_reason(contact)
      link = CampaignAudienceLink.for_campaign(@campaign)
      return CampaignJourney::AudienceContacts::CHANNEL_DISABLED_REASON if link && !audience_whatsapp_on?(link)

      return unless company_required? && WhatsappApiCampaigns::TemplateRenderer.company_name(contact).nil?

      CampaignJourney::WhatsappApiAudience::MISSING_COMPANY_REASON
    end

    def audience_whatsapp_on?(link)
      return @audience_whatsapp_on if defined?(@audience_whatsapp_on)

      @audience_whatsapp_on = CampaignJourney::AudienceContacts.whatsapp_enabled?(link.campaign_import)
    end

    def company_required?
      return @company_required if defined?(@company_required)

      uses_company = WhatsappApiCampaigns::TemplateRenderer.variables_in(@campaign.message_body)
                                                           .include?(WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE)
      @company_required = uses_company && CampaignJourney::WhatsappApiAudience.company_default(@campaign).nil?
    end
  end

  # WhatsappApiCampaigns::DeliveryEngine: the default company text of the campaign, if any.
  module Delivery
    private

    def recipient_variables(recipient)
      default = CampaignJourney::WhatsappApiAudience.company_default(@campaign)
      default ? super.merge(WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE => default) : super
    end
  end
end
