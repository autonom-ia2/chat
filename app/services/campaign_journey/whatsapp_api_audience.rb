# WhatsApp API campaigns of the journey (#999, PRD §6.3, §8.3 and §8.6; acceptance N2, D7).
# Prepended by config/initializers/campaign_journey.rb; the engine (WhatsappApiCampaigns::*)
# keeps its behaviour for campaigns without an audience link.
#
# Per-person tokens: {{contact.company}} (the contact's company) and {{publico.<key>}} (the
# audience's extra columns, CampaignJourney::AudienceColumns). A person without a value and
# without the campaign's default text for that token is skipped (cancelled) with "falta empresa"
# or "falta <key>" — the same rule as the WhatsApp Oficial variables (B1b).
module CampaignJourney::WhatsappApiAudience
  MISSING_COMPANY_REASON = 'falta empresa'.freeze
  COMPANY = WhatsappApiCampaigns::TemplateRenderer::COMPANY_VARIABLE

  # Values of this contact for the campaign's per-person tokens, defaults applied:
  # [{ 'publico.vencimento' => '10/2026', 'contact.company' => 'sua empresa' }, ['vencimento']]
  # The second element lists what is still missing ('empresa' or the column key).
  def self.resolve(campaign, link, contact)
    tokens = WhatsappApiCampaigns::TemplateRenderer.variables_in(campaign.message_body)
    defaults = link&.variable_defaults.to_h.compact_blank
    found = column_values(tokens, link, contact)
    found[COMPANY] = WhatsappApiCampaigns::TemplateRenderer.company_name(contact) if tokens.include?(COMPANY)
    values = found.to_h { |token, value| [token, value.presence || defaults[token]] }
    [values.compact, values.select { |_token, value| value.nil? }.keys.map { |token| missing_name(token) }]
  end

  # { 'publico.vencimento' => '10/2026' or nil } for the column tokens of the message.
  def self.column_values(tokens, link, contact)
    columns = tokens.filter_map { |token| CampaignJourney::AudienceColumns.column_key(token) }
    return {} if columns.empty?

    row = CampaignJourney::AudienceColumns.row_values(link&.campaign_import, contact.id)
    columns.to_h { |key| [CampaignJourney::AudienceColumns.token(key), row[key]] }
  end

  def self.missing_name(token)
    token == COMPANY ? 'empresa' : CampaignJourney::AudienceColumns.column_key(token)
  end

  def self.missing_reason(names)
    "falta #{names.join(', ')}"
  end

  # WhatsappApiCampaigns::AudienceResolver: a linked campaign resolves the audience's contacts
  # (same eligibility as WhatsApp Oficial, CampaignJourney::AudienceContacts) instead of labels.
  module Resolver
    private

    def contacts
      return super unless audience_link

      CampaignJourney::AudienceContacts.contacts_for(audience_link, channel: :whatsapp)
    end

    # Fails closed: the audience WhatsApp channel turned off → everyone skipped with the reason.
    # Then a person without a value for a token (and no default) is skipped with "falta …".
    # Skipped = cancelled with the reason (like opted_out).
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
      return CampaignJourney::AudienceContacts::CHANNEL_DISABLED_REASON if audience_link && !audience_whatsapp_on?

      _values, missing = CampaignJourney::WhatsappApiAudience.resolve(@campaign, audience_link, contact)
      missing.any? ? CampaignJourney::WhatsappApiAudience.missing_reason(missing) : nil
    end

    def audience_link
      return @audience_link if defined?(@audience_link)

      @audience_link = CampaignAudienceLink.for_campaign(@campaign)
    end

    def audience_whatsapp_on?
      return @audience_whatsapp_on if defined?(@audience_whatsapp_on)

      @audience_whatsapp_on = CampaignJourney::AudienceContacts.whatsapp_enabled?(audience_link.campaign_import)
    end
  end

  # WhatsappApiCampaigns::DeliveryEngine: this person's column values and the default texts.
  module Delivery
    private

    def recipient_variables(recipient)
      link = CampaignAudienceLink.for_campaign(@campaign)
      return super unless link

      values, _missing = CampaignJourney::WhatsappApiAudience.resolve(@campaign, link, recipient.contact)
      super.merge(values)
    end
  end
end
