module EmailCampaigns
  class RecipientImporter
    Error = Class.new(StandardError)
    Result = Struct.new(:imported, :duplicates, :invalid, :suppressed, :total, :preflight, keyword_init: true)

    MAX_ROWS = 50_000

    def initialize(campaign, file, filename:, import: nil)
      raise ArgumentError, 'import campaign mismatch' if import && import.email_campaign_id != campaign.id

      @import = import
      @campaign = campaign
      @file = file
      @filename = filename
      @account = campaign.account
    end

    def perform
      parsed = CampaignImports::Parser.new(@file, filename: @filename).perform
      raise Error, 'unsupported_file_format' unless CampaignImports::Config.supported_formats.include?(parsed.format)

      mapper = header_mapping(parsed.headers)
      rows = data_rows(parsed)
      raise Error, 'empty_file' if rows.blank?
      raise Error, 'row_limit_exceeded' if rows.size > MAX_ROWS

      import_rows(rows, mapper)
    end

    private

    def header_mapping(headers)
      result = CampaignImports::HeaderMapper.new(headers, mode: :email).perform
      raise Error, result.errors.join(',') if result.errors.present?

      result
    end

    def data_rows(parsed)
      parsed.rows.reject { |row| row.values.all? { |v| v.to_s.strip.empty? } }
    end

    BATCH_SIZE = 500

    def import_rows(rows, mapper)
      suppressed = EmailSuppression.suppressed_set_for(@account)
      seen = @campaign.email_campaign_recipients.pluck(:email).to_set(&:downcase)
      stats = { imported: 0, duplicates: 0, invalid: 0, suppressed: 0 }

      ActiveRecord::Base.transaction do
        rows.each_slice(BATCH_SIZE) do |batch|
          @issues = []
          records = batch.filter_map { |row| build_recipient(row, mapper, suppressed, seen, stats) }
          # Validated above; database enforces uniqueness.
          EmailCampaignRecipient.insert_all!(records) if records.any? # rubocop:disable Rails/SkipsModelValidations
          EmailCampaignImportIssue.insert_all!(@issues) if @issues.any? # rubocop:disable Rails/SkipsModelValidations
        end
        @campaign.refresh_counters!
      end

      summary = { status: 'pending', unchecked: stats[:imported], issues: stats[:invalid] + stats[:suppressed] + stats[:duplicates] }
      Result.new(total: rows.size, **stats, preflight: summary)
    end

    def build_recipient(row, mapper, suppressed, seen, stats) # rubocop:disable Metrics/MethodLength
      email = EmailCampaigns::EmailNormalizer.normalize!(value_at(row, mapper.mapping[:email])).email
      if seen.include?(email)
        record_issue(row, mapper, 'duplicate')
        stats[:duplicates] += 1
        return
      end

      is_suppressed = suppressed.include?(email)
      recipient = EmailCampaignRecipient.new(
        email_campaign: @campaign, name: value_at(row, mapper.mapping[:name]).presence,
        email: email, status: is_suppressed ? :suppressed : :pending,
        custom_data: custom_data_for(row, mapper.extra_columns)
      )
      unless recipient.valid?(:recipient_import)
        record_issue(row, mapper, recipient.errors[:email].any? ? 'invalid_email' : 'invalid_recipient')
        stats[:invalid] += 1
        return
      end

      record_issue(row, mapper, 'suppressed') if is_suppressed
      seen << email
      stats[is_suppressed ? :suppressed : :imported] += 1
      recipient.attributes.slice('email_campaign_id', 'name', 'email', 'status', 'custom_data')
    rescue EmailCampaigns::EmailNormalizer::Error => e
      record_issue(row, mapper, e.message)
      stats[:invalid] += 1
      nil
    end

    def record_issue(row, mapper, reason)
      @issues << { email_campaign_id: @campaign.id, email_campaign_import_id: @import&.id, row_number: row.row_number,
                   raw_address: row.values[mapper.mapping[:email]].to_s.first(320), reason_code: reason, created_at: Time.current }
    end

    def custom_data_for(row, extra_columns)
      extra_columns.transform_values { |index| value_at(row, index) }
    end

    def value_at(row, index)
      return '' if index.nil?

      row.values[index].to_s.strip
    end
  end
end
