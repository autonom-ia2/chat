# WhatsApp Oficial recipients of the campaign journey (#1005, PRD §8.0-3 and §8.3; acceptance
# D2, D4, B1b). Prepended into Whatsapp::OneoffCampaignService (Enterprise path, where
# CampaignRecipient exists) by config/initializers/campaign_journey.rb, on top of
# Enterprise::Whatsapp::OneoffCampaignService — neither file is edited.
#
# - D2: an audience campaign registers one `queued` recipient per eligible contact before the
#   first message (bulk insert, idempotent per campaign + contact) and only processes queued
#   ones; after the run no recipient is left without a final status.
# - D4: an unexpected error on one recipient marks it `failed` with a reason; the others go on.
#   Provider errors keep Enterprise's handling (Meta's error_user_msg on the recipient).
# - B1b: variables bound to the audience are resolved per person; without a value and without
#   a default the recipient is `skipped` with "falta {{N}}".
# D2/D4 handling (queued sweep, per-recipient rescue) also applies to old label campaigns —
# decided with the product owner: their audience is unchanged, only no one is left without status.
# Uses #audience_link from CampaignJourney::AudienceContacts (prepended alongside).
module CampaignJourney::WhatsappOneoffRecipients
  NOT_PROCESSED_REASON = 'Recipient was not processed'.freeze
  INSERT_BATCH_SIZE = 1000

  private

  def register_queued_recipients(contacts)
    contacts.in_batches(of: INSERT_BATCH_SIZE) do |batch|
      now = Time.current
      rows = batch.pluck(:id).map do |contact_id|
        { account_id: campaign.account_id, campaign_id: campaign.id, contact_id: contact_id, inbox_id: campaign.inbox_id,
          status: CampaignRecipient.statuses[:queued], created_at: now, updated_at: now }
      end
      CampaignRecipient.insert_all(rows, unique_by: %i[campaign_id contact_id]) if rows.any? # rubocop:disable Rails/SkipsModelValidations
    end
    Rails.logger.info "Registered queued recipients for campaign #{campaign.id}"
    campaign.campaign_recipients.queued.includes(:contact).order(:id).to_a
  end

  def process_recipient(recipient)
    super
  rescue StandardError => e
    Rails.logger.error "[CampaignJourney] campaign=#{campaign.id} recipient=#{recipient.id} #{e.class}"
    recipient.mark_failed!(message: "Unexpected error while sending (#{e.class.name})")
  end

  def process_recipients(recipients)
    super
    campaign.campaign_recipients.queued.find_each { |recipient| recipient.mark_failed!(message: NOT_PROCESSED_REASON) }
  end

  def recipient_template_params(recipient, contact)
    return super unless audience_variables&.any?

    values, missing = audience_variables.resolve(contact, audience_extra_values[contact.id])
    if missing.any?
      recipient.mark_skipped!(CampaignJourney::VariableBindings.missing_reason(missing))
      return
    end

    params = super
    params && with_variable_values(params, contact, values)
  end

  # The message kept on the recipient shows what this person received.
  def rendered_message_content(contact)
    values = resolved_values[contact.id]
    return super unless values

    values.reduce(campaign.message.to_s) { |text, (key, value)| text.gsub("{{#{key}}}", value) }
  end

  # Values go in after Liquid ran on the template, so spreadsheet text is never parsed as Liquid.
  def with_variable_values(params, contact, values)
    resolved_values[contact.id] = values
    params = params.deep_dup
    processed = params['processed_params'] = params['processed_params'].to_h
    processed['body'] = processed['body'].to_h.merge(values)
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

  # contact_id => extra_values of the audience row (the first row wins when two rows share a contact).
  def audience_extra_values
    @audience_extra_values ||= begin
      rows = audience_link.campaign_import&.campaign_import_rows
      rows ? rows.status_imported.where.not(contact_id: nil).order(row_number: :desc).pluck(:contact_id, :extra_values).to_h : {}
    end
  end
end
