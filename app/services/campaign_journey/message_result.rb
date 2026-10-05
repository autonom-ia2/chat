# Result of a message campaign (#1007, PRD §6.5): WhatsApp Oficial, SMS and WhatsApp API. Subclasses
# say where the recipients live and how their statuses read; this class builds the numbers, the
# per-person page and the export rows the same way for all of them.
#
# Every recipient has exactly one situation, so (E1)
#   Enviadas + Falharam + Puladas + Na fila = Público
# "Enviadas" counts every accepted message (sent, delivered and read); "Entregues" includes "Lidas".
# "Responderam" are recipients whose conversation got the campaign mark (CampaignJourney::ResultReplies).
class CampaignJourney::MessageResult
  PER_PAGE = 25
  ROW_INCLUDES = %i[contact].freeze
  REPLIED = 'replied'.freeze

  attr_reader :campaign

  def initialize(campaign, account:)
    @campaign = campaign
    @account = account
  end

  def source_id
    CampaignJourney::CampaignMarks.source_id_for(campaign)
  end

  def filters
    self.class::FILTERS.keys + [REPLIED]
  end

  def totals
    counts = status_counts
    statuses = ->(filter) { self.class::FILTERS.fetch(filter).sum { |status| counts.fetch(status, 0) } }
    {
      audience: counts.values.sum,
      sent: statuses.call('sent'),
      delivered: tracks?('delivered') ? statuses.call('delivered') : nil,
      read: tracks?('read') ? statuses.call('read') : nil,
      failed: statuses.call('failed'),
      skipped: statuses.call('skipped'),
      queued: statuses.call('queued'),
      replied: replied_contact_ids.size
    }
  end

  def page(filter:, page:, visible_conversations:)
    records = scope(filter).includes(self.class::ROW_INCLUDES).order(:id).page(page).per(PER_PAGE)
    links = replies.conversations_by_contact(records.map(&:contact_id), visible_conversations)
    replied = replied_contact_ids.to_set
    {
      rows: records.map do |record|
        row(record).merge(replied: replied.include?(record.contact_id), conversation_display_id: links[record.contact_id])
      end,
      meta: { count: records.total_count, current_page: records.current_page, per_page: PER_PAGE, total_pages: records.total_pages }
    }
  end

  # Unordered relation for CampaignJourney::ResultExport (it walks it by id).
  def scope(filter)
    return recipients.where(contact_id: replied_contact_ids) if filter == REPLIED
    return recipients if filter.blank?

    recipients.where(status: self.class::FILTERS.fetch(filter).flat_map { |status| raw_statuses(status) })
  end

  def export_rows(records)
    records = records_with_contacts(records)
    replied = replied_contact_ids.to_set
    records.map { |record| row(record).merge(replied: replied.include?(record.contact_id)) }
  end

  private

  def tracks?(filter)
    self.class::FILTERS.key?(filter)
  end

  def replies
    @replies ||= CampaignJourney::ResultReplies.new(@account, source_id)
  end

  def replied_contact_ids
    @replied_contact_ids ||= recipients.where(contact_id: replies.contact_ids).distinct.pluck(:contact_id)
  end

  def records_with_contacts(records)
    ActiveRecord::Associations::Preloader.new(records: records, associations: self.class::ROW_INCLUDES).call
    records
  end

  def contact_payload(contact)
    { id: contact.id, name: contact.name, phone_number: CampaignImports::PhoneNormalizer.mask(contact.phone_number) }
  end
end
