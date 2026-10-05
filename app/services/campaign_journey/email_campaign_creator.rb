# E-mail campaign of the journey (#999, contract in docs/campaigns/publicos/api-999.md): a draft
# EmailCampaign (model validations of today) linked to the audience, with its recipients
# materialized from the audience contacts. Content and design are NOT created here: the screen
# opens the existing builder flow (WelcomeChooser → AI/templates → EmailBuilderPage → details)
# with the returned id, and sending goes through the existing email endpoints and their checks.
class CampaignJourney::EmailCampaignCreator
  CHANNEL = 'email'.freeze

  def initialize(account:, campaign_import:, attributes:)
    @account = account
    @campaign_import = campaign_import
    @attributes = attributes.to_h.with_indifferent_access
  end

  def perform
    validate_channel!
    validate_audience!
    campaign = ActiveRecord::Base.transaction do
      # Locked and checked again so a concurrent delete or channel switch cannot slip in (#1005).
      @campaign_import.lock!
      validate_audience!
      campaign = EmailCampaign.create!(campaign_attributes.merge(account: @account))
      CampaignAudienceLink.create!(account: @account, campaign: campaign, campaign_import: @campaign_import)
      CampaignJourney::EmailAudienceRecipients.new(campaign).sync!
      campaign
    end
  rescue ActiveRecord::RecordInvalid => e
    raise CampaignJourney::CreatorError.new('invalid_campaign', e.record.errors.full_messages.to_sentence)
  rescue ActiveRecord::InvalidForeignKey, ActiveRecord::RecordNotFound
    raise CampaignJourney::CreatorError.new('audience_not_ready', 'The audience is no longer available')
  end

  private

  # PRD §8.10: e-mail campaigns need the e-mail campaign feature (EMAIL_CAMPAIGN_ENABLED + CRM).
  def validate_channel!
    return if EmailCampaigns::Config.enabled?

    raise CampaignJourney::CreatorError.new('channel_not_connected', 'E-mail campaigns are not enabled for this account')
  end

  def validate_audience!
    unless CampaignJourney::WhatsappCampaignCreator::READY_STATUSES.include?(@campaign_import.status)
      raise CampaignJourney::CreatorError.new('audience_not_ready', 'The audience has not finished saving')
    end
    return if CampaignJourney::AudienceContacts.email_enabled?(@campaign_import) &&
              @campaign_import.channels.to_h.dig('email', 'count').to_i.positive?

    raise CampaignJourney::CreatorError.new('channel_not_in_audience', 'This audience has no e-mail addresses enabled')
  end

  def campaign_attributes
    identity = sender_identity
    {
      name: @attributes[:title].to_s.strip, delivery_mode: delivery_mode, sender_identity: identity,
      sender_inbox: sender_inbox, from_name: @attributes[:from_name].presence, from_email: @attributes[:from_email].presence,
      reply_to_inbox_id: @attributes[:reply_to_inbox_id].presence, subject: @attributes[:subject].presence,
      preheader: @attributes[:preheader].presence, ses_configuration_set: identity&.ses_configuration_set, status: :draft
    }
  end

  def delivery_mode
    @attributes[:delivery_mode].to_s == 'direct_inbox' ? :direct_inbox : :ses
  end

  def sender_identity
    return if delivery_mode == :direct_inbox || @attributes[:sender_identity_id].blank?

    EmailSenderIdentity.find_by(account_id: @account.id, id: @attributes[:sender_identity_id])
  end

  def sender_inbox
    return unless delivery_mode == :direct_inbox

    @account.inboxes.find_by(id: @attributes[:sender_inbox_id])
  end
end
