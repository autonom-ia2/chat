# "Baixar resultado" of a campaign (#1007, E4): situation, times and reason per person, masked —
# first name and the initial of the last one, phone and e-mail masked, reasons without digit runs or
# addresses (EmailCampaigns::SafeErrorMessage). Streams through the e-mail report CSV writer
# (batches by id, formula-safe cells). The status filter of the screen applies.
class CampaignJourney::ResultExport
  MESSAGE_COLUMNS = %i[name phone status replied sent_at delivered_at read_at failed_at error_code reason].freeze
  EMAIL_COLUMNS = %i[name email status replied sent_at last_event_at reason].freeze

  def self.masked_name(name)
    parts = name.to_s.split
    return '' if parts.empty?
    return parts.first if parts.one?

    "#{parts.first} #{parts.last.first}."
  end

  def initialize(result, filter:)
    @result = result
    @filter = filter
  end

  def email?
    @result.is_a?(CampaignJourney::EmailResult)
  end

  def filename
    "campaign_#{@result.campaign_payload[:channel]}_#{@result.campaign.id}_result.csv"
  end

  def csv
    columns = email? ? EMAIL_COLUMNS : MESSAGE_COLUMNS
    EmailCampaigns::Reports::CsvExport.new(scope: @result.scope(@filter), columns: columns) do |batch|
      @result.export_rows(batch).map { |row| email? ? email_row(row) : message_row(row) }
    end
  end

  private

  def message_row(row)
    row.slice(:status, :sent_at, :delivered_at, :read_at, :failed_at, :error_code).merge(
      name: self.class.masked_name(row.dig(:contact, :name)), phone: row.dig(:contact, :phone_number),
      replied: row[:replied], reason: safe(row[:error_message] || row[:error_title])
    )
  end

  def email_row(row)
    row.slice(:email, :status, :sent_at, :last_event_at, :replied).merge(
      name: self.class.masked_name(row[:name]), reason: safe(row[:error_message])
    )
  end

  def safe(reason)
    reason.present? ? EmailCampaigns::SafeErrorMessage.call(reason) : nil
  end
end
