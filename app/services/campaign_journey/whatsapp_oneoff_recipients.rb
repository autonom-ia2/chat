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
#
# Which campaigns: linked campaigns always (otherwise they would send to no one). Unlinked
# (label) campaigns get the D2/D4 handling only while CAMPAIGN_JOURNEY_ENABLED is on — decided
# with the product owner: their audience is unchanged, only no one is left without status.
# With the flag off they run Chatwoot's code untouched (pure `super`).
# Uses #audience_link from CampaignJourney::AudienceContacts (prepended alongside).
module CampaignJourney::WhatsappOneoffRecipients
  NOT_PROCESSED_REASON = 'Recipient was not processed'.freeze
  INSERT_BATCH_SIZE = 1000

  private

  def journey_send?
    audience_link.present? || CampaignJourney::Config.enabled?
  end

  # Returns the queued recipients as a lazy, batched enumerator (never the whole list in memory).
  def register_queued_recipients(contacts)
    insert_recipients(contacts, status: :queued)
    campaign.campaign_recipients.queued.includes(:contact).find_each(batch_size: INSERT_BATCH_SIZE)
  end

  # Audience WhatsApp channel off at send time: everyone eligible is recorded as skipped.
  def skip_all_recipients(contacts, reason)
    insert_recipients(contacts, status: :skipped, error_message: reason)
    campaign.campaign_recipients.queued.update_all(status: CampaignRecipient.statuses[:skipped], error_message: reason) # rubocop:disable Rails/SkipsModelValidations
    []
  end

  def insert_recipients(contacts, status:, error_message: nil)
    contacts.in_batches(of: INSERT_BATCH_SIZE) do |batch|
      now = Time.current
      rows = batch.pluck(:id).map do |contact_id|
        { account_id: campaign.account_id, campaign_id: campaign.id, contact_id: contact_id, inbox_id: campaign.inbox_id,
          status: CampaignRecipient.statuses[status], error_message: error_message, created_at: now, updated_at: now }
      end
      CampaignRecipient.insert_all(rows, unique_by: %i[campaign_id contact_id]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    end
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

  def keep_as_sent(recipient, source_id, error)
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} accepted by Meta, mark_sent! failed: #{error.class}"
    recipient.update_columns(status: CampaignRecipient.statuses[:sent], source_id: source_id, sent_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} could not be kept as sent: #{e.class}"
  end

  def accepted_by_provider
    @accepted_by_provider ||= Set.new
  end

  def process_recipients(recipients)
    return super unless journey_send?

    super
    campaign.campaign_recipients.queued.where.not(id: accepted_by_provider.to_a).find_each do |recipient|
      recipient.mark_failed!(message: NOT_PROCESSED_REASON)
    end
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
