require 'rails_helper'
require 'csv'

# Epic integration spec groups export and import-issue contracts in the assigned file.
RSpec.describe EmailCampaigns::Reports do # rubocop:disable RSpec/SpecFilePathFormat
  describe EmailCampaigns::Reports::CsvExport do
    let(:campaign) { create(:email_campaign) }

    it 'exports more than 10,000 filtered rows in bounded batches and excludes rows beyond the initial id horizon' do
      now = Time.current
      10_001.times.each_slice(500) do |numbers|
        # Bulk fixture exercises the real export size without 10,001 model callbacks.
        EmailCampaignRecipient.insert_all!(numbers.map do |number| # rubocop:disable Rails/SkipsModelValidations
          { email_campaign_id: campaign.id, email: "csv#{number}@example.org", name: 'Export cohort', status: 2, created_at: now, updated_at: now }
        end)
      end
      create(:email_campaign_recipient, email_campaign: campaign, name: 'Excluded', status: :pending)
      query = EmailCampaigns::RecipientQuery.new(campaign, q: 'Export cohort', status: 'failed', problem: true, page: 2)
      batch_sizes = []
      export = described_class.new(scope: query.call, columns: described_class::RECIPIENT_COLUMNS) do |batch|
        batch_sizes << batch.length
        EmailCampaigns::Presentation::Recipients.new(campaign, batch).call
      end
      create(:email_campaign_recipient, email_campaign: campaign, name: 'Export cohort', status: :failed)
      contents = export.each.to_a.join
      rows = CSV.parse(contents.delete_prefix("\uFEFF"), headers: true)
      expect(contents).to start_with("\uFEFF")
      expect(rows.size).to eq(10_001)
      expect(batch_sizes.max).to be <= 500
      expect(rows.map { |row| row['id'].to_i }).to eq(rows.map { |row| row['id'].to_i }.sort)
      expect(rows.headers.first(8)).to eq(%w[id name email status attempts last_event_at opens clicks])
    end

    it 'neutralizes formulas after whitespace/control characters in every textual column and preserves robust CSV quoting' do
      recipient = create(:email_campaign_recipient, email_campaign: campaign, name: " \t\r=HYPERLINK(\"example.org\")",
                                                    preflight_suggestion: "\n+example.org", preflight_reason_code: "\t@reason")
      export = described_class.new(scope: campaign.email_campaign_recipients, columns: described_class::RECIPIENT_COLUMNS) do |batch|
        EmailCampaigns::Presentation::Recipients.new(campaign, batch).call
      end
      row = CSV.parse(export.each.to_a.join.delete_prefix("\uFEFF"), headers: true).first
      expect(row['name']).to eq("'#{recipient.name}")
      expect(row['preflight_suggestion']).to eq("'\n+example.org")
      expect(row['preflight_reason']).to eq("'\t@reason")
      %w[=formula +formula -formula @formula].each do |value|
        expect(described_class.safe_cell(value)).to eq("'#{value}")
      end
      expect(described_class.safe_cell('name@example.org')).to eq('name@example.org')
    end

    it 'refreshes suppression predicates and public reasons after every streamed batch' do
      travel_to Time.zone.parse('2026-09-17 12:00:00 UTC') do
        EmailCampaignRecipient.insert_all!(Array.new(500) do |number| # rubocop:disable Rails/SkipsModelValidations
          { email_campaign_id: campaign.id, email: "batch#{number}@example.org", status: 2,
            created_at: Time.current, updated_at: Time.current }
        end)
        last_row = create(:email_campaign_recipient, email_campaign: campaign, status: :failed)
        expiring = create(:email_campaign_recipient, email_campaign: campaign, preflight_status: 'valid',
                                                     preflight_checked_at: Time.current, preflight_valid_until: 1.day.from_now)
        EmailSuppressionState.create!(account: campaign.account, email: expiring.email, reason: 'temporary_failure',
                                      active: true, expires_at: 1.minute.from_now)
        query = EmailCampaigns::RecipientQuery.new(campaign, problem: true)
        export = described_class.new(scope: -> { query.call }, columns: described_class::RECIPIENT_COLUMNS) do |batch|
          EmailCampaigns::Presentation::Recipients.new(campaign, batch).call
        end
        chunks = []
        export.each do |chunk|
          chunks << chunk
          next unless chunks.size == 3 # BOM, headers, first row: the first batch is already presented.

          EmailSuppression.create!(account: campaign.account, email: last_row.email, reason: 'manual')
          travel 2.minutes
        end
        rows = CSV.parse(chunks.join.delete_prefix("\uFEFF"), headers: true)
        expect(rows.size).to eq(501)
        expect(rows[-1]['id'].to_i).to eq(last_row.id)
        expect(rows[-1]['suppression_reason']).to eq('manual')
        expect(rows.map { |row| row['email'] }).not_to include(expiring.email)
      end
    end
  end

  describe EmailCampaigns::Reports::ImportIssuesQuery do
    let(:campaign) { create(:email_campaign) }

    it 'uses actual raw_address schema and combines escaped search/reason for read and export' do
      issue = campaign.email_campaign_import_issues.create!(row_number: 3, raw_address: 'odd_%@example.org', reason_code: 'invalid_email')
      campaign.email_campaign_import_issues.create!(row_number: 4, raw_address: 'other@example.org', reason_code: 'duplicate')
      query = described_class.new(campaign, q: '_%', reason: 'invalid_email')
      expect(query.call.pluck(:id)).to eq([issue.id])
      expect(described_class.present(query.paginated)).to eq([
                                                               { id: issue.id, row_number: 3,
                                                                 raw_email: 'odd_%@example.org', email: 'odd_%@example.org',
                                                                 reason_code: 'invalid_email', suggestion: nil, classification: 'invalid' }
                                                             ])
      expect(query.meta).to include(count: 1, total_pages: 1)
      export = EmailCampaigns::Reports::CsvExport.new(scope: query.call, columns: EmailCampaigns::Reports::CsvExport::ISSUE_COLUMNS) do |batch|
        described_class.present(batch)
      end
      expect(CSV.parse(export.each.to_a.join.delete_prefix("\uFEFF"), headers: true).first['raw_email']).to eq(issue.raw_address)
    end

    it 'sanitizes untrusted import issues and excludes another campaign' do
      campaign.email_campaign_import_issues.create!(
        row_number: 3, raw_address: "\t=example.org", reason_code: 'invalid_email', suggestion: ' @example.org'
      )
      other = create(:email_campaign)
      other.email_campaign_import_issues.create!(row_number: 3, raw_address: 'private@example.org', reason_code: 'invalid_email')
      query = described_class.new(campaign)
      export = EmailCampaigns::Reports::CsvExport.new(scope: query.call, columns: EmailCampaigns::Reports::CsvExport::ISSUE_COLUMNS) do |batch|
        described_class.present(batch)
      end
      contents = export.each.to_a.join
      expect(contents).not_to include('private@example.org')
      row = CSV.parse(contents.delete_prefix("\uFEFF"), headers: true).first
      expect(row['raw_email']).to eq("'\t=example.org")
      expect(row['suggestion']).to eq("' @example.org")
    end

    it 'rejects malformed reason and page values' do
      [{ reason: ['duplicate'] }, { reason: '../all' }, { page: '0' }].each do |params|
        expect { described_class.new(campaign, params) }.to raise_error(EmailCampaigns::Reports::Parameters::Invalid)
      end
    end

    it 'presents an overlong name as recipient-data review without mislabeling a valid email' do
      csv = "name,email\n#{'N' * 256},valid@example.org\n"
      EmailCampaigns::RecipientImporter.new(campaign, csv, filename: 'names.csv').perform
      query = described_class.new(campaign, reason: 'invalid_recipient')
      expect(described_class.present(query.call).sole).to include(
        raw_email: 'valid@example.org', reason_code: 'invalid_recipient', classification: 'review', row_number: 2
      )
      expect(described_class.new(campaign, reason: 'invalid_email').call).to be_empty
    end

    it 'returns only whitelisted latest import statistics and explicit original-row denominator' do
      campaign.email_campaign_imports.create!(status: :failed, result: { total: 2, invalid: 1, private: 'never expose' })
      result = EmailCampaigns::Presentation::ImportSummary.new(campaign).call
      expect(result).to include(status: 'failed', denominator: 2, result: { 'total' => 2, 'invalid' => 1 })
      expect(result.to_json).not_to include('never expose')
    end
  end
end
