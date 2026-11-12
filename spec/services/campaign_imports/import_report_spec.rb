require 'rails_helper'

# The report file the Importer attaches when an import ends: its final status and counts.
RSpec.describe CampaignImports::ImportReport, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }

  def import_named(filename)
    create_campaign_import(account: account_and_user.first, user: account_and_user.last, content: "nome,telefone\n", filename: filename)
  end

  def metrics(campaign_import)
    CSV.parse(campaign_import.report_csv.download, headers: true).to_h { |row| [row['metric'], row['value']] }
  end

  it 'attaches the final counts under the name of the uploaded file, without its extension' do
    campaign_import = import_named('base.junho.csv')

    described_class.new(campaign_import).attach(imported_count: 5, existing_count: 2, failed_count: 0)

    expect(campaign_import.report_csv.filename.to_s).to eq('base.junho_report.csv')
    expect(metrics(campaign_import)).to include(
      'status' => 'completed', 'imported_contacts_count' => '5', 'existing_contacts_count' => '2',
      'created_contacts_count' => '3', 'failed_contacts_count' => '0', 'batch_count' => '2'
    )
  end

  it 'reports completed_with_failures when a row failed' do
    campaign_import = import_named('base.csv')

    described_class.new(campaign_import).attach(imported_count: 4, existing_count: 0, failed_count: 1)

    expect(metrics(campaign_import)).to include('status' => 'completed_with_failures', 'failed_contacts_count' => '1')
  end

  it 'names the file after the import when the uploaded file has no name to use' do
    campaign_import = import_named('base.csv')
    campaign_import.update!(source_filename: nil)

    described_class.new(campaign_import).attach(imported_count: 1, existing_count: 0, failed_count: 0)

    expect(campaign_import.report_csv.filename.to_s).to eq("campaign_import_#{campaign_import.id}_report.csv")
  end

  it 'replaces the report of an earlier pass instead of keeping two' do
    campaign_import = import_named('base.csv')

    described_class.new(campaign_import).attach(imported_count: 2, existing_count: 0, failed_count: 0)
    described_class.new(campaign_import).attach(imported_count: 5, existing_count: 0, failed_count: 0)

    expect(metrics(campaign_import.reload)).to include('imported_contacts_count' => '5')
    expect(ActiveStorage::Attachment.where(record: campaign_import, name: 'report_csv').count).to eq(1)
  end
end
