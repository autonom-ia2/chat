# E-mail campaign result (#1007). The detailed numbers, chart, link clicks, per-person table,
# filtered export and health keep coming from the e-mail reports API (EmailCampaigns::Reports::*),
# exactly as the old Gestão de campanhas read them. This adds what the journey result needs on top:
# the E1 groups (CampaignJourney::EmailResultTotals), "Responderam" (contacts whose conversation got
# the campaign mark, #1002) with the conversation to open, and the masked "Baixar resultado" (E4).
class CampaignJourney::EmailResult
  PER_PAGE = 25
  REPLIED = 'replied'.freeze
  ROW_INCLUDES = [].freeze

  attr_reader :campaign

  def initialize(campaign, account:)
    @campaign = campaign
    @account = account
  end

  def source_id
    CampaignJourney::CampaignMarks.source_id_for(campaign)
  end

  def filters
    [REPLIED]
  end

  def processing?
    campaign.sending? || campaign.scheduled?
  end

  def campaign_payload
    {
      id: campaign.id, channel: CampaignJourney::ResultFinder::EMAIL, name: campaign.name, status: campaign.status,
      processing: processing?, delivery_mode: campaign.delivery_mode, from_email: campaign.from_email,
      sent_at: campaign.sent_at, started_at: campaign.first_sent_at, scheduled_at: campaign.scheduled_at,
      audience: CampaignJourney::ResultFinder.audience_of(campaign)
    }
  end

  def totals
    CampaignJourney::EmailResultTotals.new(campaign).call.merge(replied: replies.contact_ids.size)
  end

  # "Como foi esta campanha" (#990): numbers of this campaign for one period (7, 14, 30 or all).
  def period_metrics(period)
    CampaignJourney::EmailPeriodMetrics.new(campaign, period: period).call
  end

  # Only "Responderam" lives here; every other person filter is the e-mail reports table.
  def page(page:, visible_conversations:, **)
    conversations = replies.latest_conversations.includes(:contact).page(page).per(PER_PAGE)
    visible = visible_conversations.where(id: conversations.map(&:id)).pluck(:id).to_set
    {
      rows: conversations.map { |conversation| replied_row(conversation, visible) },
      meta: { count: conversations.total_count, current_page: conversations.current_page, per_page: PER_PAGE,
              total_pages: conversations.total_pages }
    }
  end

  def scope(filter)
    recipients = campaign.email_campaign_recipients
    filter == REPLIED ? recipients.where(contact_id: replies.contact_ids) : recipients
  end

  def export_rows(records)
    replied = replies.contact_ids.to_set
    records.map do |record|
      {
        name: record.name, email: EmailCampaigns::EmailNormalizer.mask(record.email.to_s), status: record.status,
        sent_at: record.sent_at, last_event_at: record.last_event_at,
        error_message: record.preflight_reason_code.presence || record.last_error,
        replied: record.contact_id.present? && replied.include?(record.contact_id)
      }
    end
  end

  private

  def replies
    @replies ||= CampaignJourney::ResultReplies.new(@account, source_id)
  end

  def replied_row(conversation, visible)
    contact = conversation.contact
    {
      id: contact.id, status: REPLIED,
      contact: { id: contact.id, name: contact.name, email: contact.email.present? ? EmailCampaigns::EmailNormalizer.mask(contact.email) : nil },
      conversation_display_id: visible.include?(conversation.id) ? conversation.display_id : nil
    }
  end
end
