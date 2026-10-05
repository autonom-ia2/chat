# Result of a WhatsApp API campaign (#1007). The engine records sent / failed / cancelled per
# recipient but no delivery or read receipt, so "Entregues" and "Lidas" do not exist here.
# pending and sending read as "Na fila"; cancelled (refused, discarded lead, missing variable,
# channel turned off) reads as "Puladas" with its reason (api-999.md §5).
class CampaignJourney::WhatsappApiResult < CampaignJourney::MessageResult
  FILTERS = {
    'queued' => %w[queued],
    'sent' => %w[sent],
    'failed' => %w[failed],
    'skipped' => %w[skipped]
  }.freeze
  RAW_STATUSES = {
    'queued' => %w[pending sending],
    'sent' => %w[sent],
    'failed' => %w[failed],
    'skipped' => %w[cancelled]
  }.freeze
  STATUS = RAW_STATUSES.flat_map { |status, raws| raws.map { |raw| [raw, status] } }.to_h.freeze
  ROW_INCLUDES = %i[contact message].freeze

  def recipients
    campaign.whatsapp_api_campaign_recipients
  end

  def processing?
    campaign.running? || campaign.scheduled? || recipients.exists?(status: RAW_STATUSES['queued'])
  end

  def campaign_payload
    {
      id: campaign.id, channel: CampaignJourney::ResultFinder::WHATSAPP_API, name: campaign.title, status: campaign.status,
      processing: processing?, inbox: campaign.inbox && { id: campaign.inbox.id, name: campaign.inbox.name },
      scheduled_at: campaign.scheduled_at, started_at: campaign.started_at, completed_at: campaign.completed_at,
      audience: CampaignJourney::ResultFinder.audience_of(campaign)
    }
  end

  private

  def status_counts
    recipients.group(:status).count.each_with_object(Hash.new(0)) { |(raw, count), counts| counts[STATUS.fetch(raw)] += count }
  end

  def raw_statuses(status)
    RAW_STATUSES.fetch(status)
  end

  def row(record)
    status = STATUS.fetch(record.status)
    {
      id: record.id, contact: contact_payload(record.contact), status: status,
      message_content: record.message&.content, error_code: nil, error_title: nil,
      error_message: status == 'sent' ? nil : record.last_error_message, sent_at: record.sent_at,
      delivered_at: nil, read_at: nil, failed_at: record.failed_at || record.cancelled_at
    }
  end
end
