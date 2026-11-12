module CampaignImports
  class Config
    BOOLEAN = ActiveModel::Type::Boolean.new

    class << self
      def enabled?
        BOOLEAN.cast(ENV.fetch('CAMPAIGN_IMPORT_ENABLED', false))
      end

      def max_file_size_bytes
        ENV.fetch('CAMPAIGN_IMPORT_MAX_FILE_SIZE_MB', 10).to_i.megabytes
      end

      def max_csv_rows
        ENV.fetch('CAMPAIGN_IMPORT_MAX_CSV_ROWS', 50_000).to_i
      end

      def max_xlsx_rows
        ENV.fetch('CAMPAIGN_IMPORT_MAX_XLSX_ROWS', 20_000).to_i
      end

      def max_xlsx_uncompressed_size_bytes
        ENV.fetch('CAMPAIGN_IMPORT_MAX_XLSX_UNCOMPRESSED_SIZE_MB', 50).to_i.megabytes
      end

      def max_batches
        ENV.fetch('CAMPAIGN_IMPORT_MAX_BATCHES', 1000).to_i
      end

      def supported_formats
        %w[csv xlsx]
      end

      def warn_batches_above
        ENV.fetch('CAMPAIGN_IMPORT_WARN_BATCHES_ABOVE', 200).to_i
      end

      def allow_concurrent?
        BOOLEAN.cast(ENV.fetch('CAMPAIGN_IMPORT_ALLOW_CONCURRENT', false))
      end

      def original_file_retention
        7.days
      end

      def generated_file_retention
        30.days
      end

      # #2921: an import still `importing` with no row written for this long lost its worker
      # (CampaignImports::StalledImportsJob puts it back in the queue).
      def stalled_import_after
        15.minutes
      end
    end
  end
end
