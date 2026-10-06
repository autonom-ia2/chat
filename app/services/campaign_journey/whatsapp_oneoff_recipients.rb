# WhatsApp Oficial recipients of the campaign journey (#1005, PRD §8.0-3 and §8.3; acceptance
# D2, D4, B1b). Prepended into Whatsapp::OneoffCampaignService (Enterprise path, where
# CampaignRecipient exists) by config/initializers/campaign_journey.rb, on top of
# Enterprise::Whatsapp::OneoffCampaignService — neither file is edited.
#
# - D2: an audience campaign registers one `queued` recipient per eligible contact before the
#   first message (bulk insert, idempotent per campaign + contact) and only processes queued
#   ones, walked in batches; after the run no recipient is left without a final status.
# - D4: an unexpected error on one recipient BEFORE Meta accepted the message marks it `failed`
#   with a reason; the others go on. Once Meta accepted a message it is never marked failed
#   (if saving `sent` fails, the status is forced to sent and the error logged) and, being no
#   longer queued, it is never sent again. Provider errors keep Enterprise's handling (Meta's
#   error_user_msg on the recipient).
# - B1b: variables bound to the audience are resolved per person; without a value and without
#   a default the recipient is `skipped` with "falta {{N}}".
# - P2 (#1002): an audience campaign records each accepted message in the contact's existing
#   conversation (CampaignJourney::SentMessageRecorder); no conversation is created and no
#   campaign mark is written at send time (D14).
#
# Which campaigns: linked campaigns always (otherwise they would send to no one). Unlinked
# (label) campaigns get the D2/D4 handling only while CAMPAIGN_JOURNEY_ENABLED is on — decided
# with the product owner: their audience is unchanged, only no one is left without status.
# With the flag off they run Chatwoot's code untouched (pure `super`).
# Uses #audience_link from CampaignJourney::AudienceContacts (prepended alongside) and the
# recipient bookkeeping shared with SMS (CampaignJourney::RecipientTracking, #1004).
module CampaignJourney::WhatsappOneoffRecipients
  include CampaignJourney::RecipientTracking

  private

  def journey_send?
    audience_link.present? || CampaignJourney::Config.enabled?
  end

  def process_recipient(recipient)
    return super unless journey_send?

    begin
      super
    rescue StandardError => e
      handle_unexpected_error(recipient, e)
    end
  end

  def handle_unexpected_error(recipient, error)
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} #{error.class}"
    return if accepted_by_provider.include?(recipient.id)

    recipient.mark_failed!(message: "Unexpected error while sending (#{error.class.name})")
  end

  def update_recipient_from_provider_response(recipient, source_id)
    return super unless journey_send? && source_id.present?

    accepted_by_provider << recipient.id
    begin
      super
    rescue StandardError => e
      keep_as_sent(recipient, source_id, e)
    end
  end

  # P2 (#1002): the message Meta accepted goes into the contact's existing conversation (audience
  # campaigns only; label campaigns keep Chatwoot's behaviour). No conversation is created.
  def send_whatsapp_template_message(recipient:, to:, template_params:)
    result = super
    record_sent_message(recipient, to)
    result
  end

  def record_sent_message(recipient, destination)
    return unless audience_link.present? && accepted_by_provider.include?(recipient.id)

    CampaignJourney::SentMessageRecorder.new(campaign: campaign, recipient: recipient).record_at_send(destination)
  end

  def process_recipients(recipients)
    return super unless journey_send?

    super
    fail_unprocessed_recipients
  end

  def recipient_template_params(recipient, contact)
    return super unless audience_variables&.any?

    values, missing = audience_variables.resolve(contact, audience_extra_values(contact.id))
    if missing.any?
      recipient.mark_skipped!(CampaignJourney::VariableBindings.missing_reason(missing))
      return
    end

    params = super
    params && with_variable_values(params, contact, values)
  end

  # The message kept on the recipient shows what this person received (single literal pass).
  def rendered_message_content(contact)
    values = resolved_values.delete(contact.id)
    return super unless values

    CampaignJourney::TemplatePlaceholders.render(campaign.message.to_s, values)
  end

  # Values go in after Liquid ran on the template (body, TEXT header and URL buttons, #993), so spreadsheet text is never parsed as Liquid.
  def with_variable_values(params, contact, values)
    resolved_values[contact.id] = values
    params = params.deep_dup
    params['processed_params'] = CampaignJourney::TemplateVariableKeys.apply(params['processed_params'], values)
    params
  end

  def resolved_values
    @resolved_values ||= {}
  end

  def audience_variables
    return @audience_variables if defined?(@audience_variables)

    link = audience_link
    @audience_variables = link && CampaignJourney::VariableBindings.new(link.variable_bindings, link.variable_defaults)
  end

  # extra_values of the contact's audience row (the first row wins), read per recipient.
  def audience_extra_values(contact_id)
    rows = audience_link.campaign_import&.campaign_import_rows
    return {} unless rows

    rows.status_imported.where(contact_id: contact_id).order(:row_number).pick(:extra_values).to_h
  end
end
