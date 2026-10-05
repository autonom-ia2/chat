# "Vão receber" before creating a journey campaign (#993, PRD §6.4, B8, B1b; decision of 05/10):
# the exact number the send will reach, with the same rules the creators and the send use, and
# each person counted in ONE reason only, in this order:
#   channel_disabled → opted_out (#737) → suppressed e-mail (unsubscribed / bounced / suppressed)
#   → missing_variables (a variable without value and without default, "falta {{N}}").
# Eligibility is CampaignJourney::AudienceContacts (row consent: the row had that mobile/e-mail
# and the contact still has it). Variables: CampaignJourney::VariableBindings (WhatsApp Oficial)
# CampaignJourney::WhatsappApiAudience (WhatsApp API tokens) and CampaignJourney::SmsMessage (SMS
# tokens, #1004: same phone rule as WhatsApp, its own channel switch). Nothing is written.
class CampaignJourney::RecipientPreview
  CHANNELS = %w[whatsapp_cloud whatsapp_api sms email].freeze
  UNSUBSCRIBE_REASONS = %w[unsubscribe].freeze
  BOUNCE_REASONS = %w[hard_bounce].freeze

  # Stand-ins with the two readers WhatsappApiAudience.resolve uses (no campaign exists yet).
  ApiCampaign = Struct.new(:message_body)
  ApiLink = Struct.new(:campaign_import, :variable_defaults)

  def initialize(campaign_import, channel:, variable_bindings: {}, variable_defaults: {}, message_body: nil)
    @campaign_import = campaign_import
    @account = campaign_import.account
    @channel = channel.to_s
    @variable_bindings = variable_bindings.to_h
    @variable_defaults = variable_defaults.to_h
    @message_body = message_body.to_s
  end

  def perform
    raise ArgumentError, 'unsupported_channel' unless CHANNELS.include?(@channel)

    @channel == 'email' ? email_preview : whatsapp_preview
  end

  private

  def result(total, reasons, missing_by_variable = {})
    reasons = reasons.select { |_reason, count| count.positive? }
    { 'channel' => @channel, 'total' => total, 'receive' => total - reasons.values.sum,
      'reasons' => reasons, 'missing_by_variable' => missing_by_variable }
  end

  # ---- WhatsApp (Oficial and API) ----

  def whatsapp_preview
    ids = CampaignJourney::AudienceContacts.whatsapp_contact_ids(@campaign_import, account: @account)
    return result(ids.size, 'channel_disabled' => ids.size) unless phone_channel_enabled?

    contacts = @account.contacts.where(id: ids)
    opted_out = contacts.where.not(opted_out_at: nil).count
    missing, by_variable = missing_variables(contacts.where(opted_out_at: nil))
    result(ids.size, { 'opted_out' => opted_out, 'missing_variables' => missing }, by_variable)
  end

  def missing_variables(contacts)
    by_variable = Hash.new(0)
    missing = 0
    preloaded(contacts).find_each do |contact|
      keys = missing_keys(contact)
      next if keys.empty?

      missing += 1
      keys.each { |key| by_variable[key] += 1 }
    end
    [missing, by_variable]
  end

  def phone_channel_enabled?
    return CampaignJourney::AudienceContacts.sms_enabled?(@campaign_import) if @channel == 'sms'

    CampaignJourney::AudienceContacts.whatsapp_enabled?(@campaign_import)
  end

  def missing_keys(contact)
    if @channel == 'sms'
      _text, missing = sms_message.render_for(contact)
      return missing
    end
    if @channel == 'whatsapp_api'
      _values, missing = CampaignJourney::WhatsappApiAudience.resolve(api_campaign, api_link, contact)
      return missing
    end
    return [] unless bindings.any?

    _values, missing = bindings.resolve(contact, extra_values[contact.id])
    missing
  end

  def bindings
    @bindings ||= CampaignJourney::VariableBindings.new(@variable_bindings, @variable_defaults)
  end

  def sms_message
    @sms_message ||= CampaignJourney::SmsMessage.new(@message_body, campaign_import: @campaign_import, defaults: @variable_defaults)
  end

  def api_campaign
    @api_campaign ||= ApiCampaign.new(@message_body)
  end

  def api_link
    @api_link ||= ApiLink.new(@campaign_import, @variable_defaults)
  end

  # extra_values of each contact's first imported row, read once.
  def extra_values
    @extra_values ||= @campaign_import.campaign_import_rows.status_imported.where.not(contact_id: nil)
                                      .order(:row_number).pluck(:contact_id, :extra_values)
                                      .each_with_object({}) { |(id, values), map| map[id] ||= values.to_h }
  end

  def preloaded(contacts)
    Contact.reflect_on_association(:company) ? contacts.includes(:company) : contacts
  end

  # ---- E-mail ----

  def email_preview
    matches = CampaignJourney::AudienceContacts.email_matches(@campaign_import, account: @account)
    return result(matches.size, 'channel_disabled' => matches.size) unless CampaignJourney::AudienceContacts.email_enabled?(@campaign_import)

    opted_ids = @account.contacts.where(id: matches.map(&:contact_id)).where.not(opted_out_at: nil).pluck(:id).to_set
    reachable = matches.reject { |match| opted_ids.include?(match.contact_id) }
    suppressed = suppression_buckets(reachable.map(&:email))
    result(matches.size, { 'opted_out' => matches.size - reachable.size }.merge(suppressed))
  end

  def suppression_buckets(emails)
    buckets = { 'unsubscribed' => 0, 'bounced' => 0, 'suppressed' => 0 }
    EmailSuppression.blocking_reasons_for(@account, emails).each_value do |reason|
      buckets[bucket_for(reason)] += 1
    end
    buckets
  end

  def bucket_for(reason)
    return 'unsubscribed' if UNSUBSCRIBE_REASONS.include?(reason)
    return 'bounced' if BOUNCE_REASONS.include?(reason)

    'suppressed'
  end
end
