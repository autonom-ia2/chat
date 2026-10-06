# Result of a Chatwoot one-off campaign: WhatsApp Oficial and SMS (#1007). Recipients are the
# Enterprise `campaign_recipients` (WhatsApp Oficial since #993/#1005; SMS once #1004 records them —
# until then an SMS campaign has no rows and the result says so). Statuses are already the result's:
# queued, sent, delivered, read, failed, skipped.
class CampaignJourney::CampaignRecipientsResult < CampaignJourney::MessageResult
  # filter => statuses (sent includes delivered and read; delivered includes read)
  FILTERS = {
    'queued' => %w[queued],
    'sent' => %w[sent delivered read],
    'delivered' => %w[delivered read],
    'read' => %w[read],
    'failed' => %w[failed],
    'skipped' => %w[skipped]
  }.freeze
  # SMS has no "read" (PRD §6.5).
  SMS_FILTERS = FILTERS.except('read').freeze

  def recipients
    return CampaignRecipient.where(campaign_id: campaign.id) if defined?(CampaignRecipient)

    # OSS install without Enterprise: no per-person record exists.
    Contact.none
  end

  def processing?
    campaign.processing? || recipients.exists?(status: 'queued')
  end

  def campaign_payload
    {
      id: campaign.display_id, channel: channel, name: campaign.title, status: campaign.campaign_status, processing: processing?,
      inbox: { id: campaign.inbox.id, name: campaign.inbox.name }, scheduled_at: campaign.scheduled_at,
      template_name: campaign.template_params.to_h['name'], audience: CampaignJourney::ResultFinder.audience_of(campaign)
    }
  end

  def channel
    CampaignJourney::ResultFinder::WHATSAPP_OFFICIAL
  end

  private

  def status_counts
    recipients.group(:status).count
  end

  def raw_statuses(status)
    [status]
  end

  def row(record)
    {
      id: record.id, contact: contact_payload(record.contact), status: record.status,
      message_content: record.message_content, error_code: record.error_code, error_title: record.error_title,
      error_message: record.error_message, sent_at: record.sent_at, delivered_at: record.delivered_at,
      read_at: record.read_at, failed_at: record.failed_at
    }
  end
end
