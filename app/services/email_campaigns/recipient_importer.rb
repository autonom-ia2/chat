module EmailCampaigns
  class RecipientImporter
    Error = Class.new(StandardError)
    Result = Struct.new(:imported, :duplicates, :invalid, :suppressed, :total, keyword_init: true)

    MAX_ROWS = 50_000

    def initialize(campaign, file, filename:)
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
          records = batch.filter_map { |row| build_recipient(row, mapper, suppressed, seen, stats) }
          EmailCampaignRecipient.insert_all!(records) if records.any? # rubocop:disable Rails/SkipsModelValidations -- validated above; DB enforces uniqueness
        end
        @campaign.refresh_counters!
      end

      Result.new(total: rows.size, **stats)
    end

    def build_recipient(row, mapper, suppressed, seen, stats) # rubocop:disable Metrics/MethodLength
      email = EmailCampaigns::EmailNormalizer.normalize!(value_at(row, mapper.mapping[:email])).email
      if seen.include?(email)
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
        stats[:invalid] += 1
        return
      end

      seen << email
      stats[is_suppressed ? :suppressed : :imported] += 1
      recipient.attributes.slice('email_campaign_id', 'name', 'email', 'status', 'custom_data')
    rescue EmailCampaigns::EmailNormalizer::Error
      stats[:invalid] += 1
      nil
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
