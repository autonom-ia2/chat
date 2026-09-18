require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientImporter do # -- focused rejected-address evidence regressions
  let(:campaign) { create(:email_campaign) }
  let(:import) { campaign.email_campaign_imports.create! }

  it 'persists a CSV NUL rejection without rolling back the valid recipient in the same batch' do
    csv = "name,email\nGood,User+Tag@example.org\nBad,bad\0mail@example.org\n"
    result = described_class.new(campaign, csv, filename: 'nul.csv', import: import).perform
    expect(result.to_h.slice(:imported, :invalid, :total)).to eq(imported: 1, invalid: 1, total: 2)
    expect(campaign.email_campaign_recipients.sole.email).to eq('user+tag@example.org')
    issue = import.email_campaign_import_issues.sole
    expect([issue.reason_code, issue.row_number, issue.raw_address]).to eq(['invalid_email', 3, 'bad\\x00mail@example.org'])
  end

  it 'persists bounded invalid UTF-8 evidence from a parsed row alongside a valid recipient' do
    bad = "bad\xFF#{'x' * 400}@example.org"
    rows = [
      CampaignImports::Parser::ParsedRow.new(row_number: 2, values: ['Good', 'User+Tag@example.org']),
      CampaignImports::Parser::ParsedRow.new(row_number: 3, values: ['', bad])
    ]
    parsed = CampaignImports::Parser::ParsedFile.new(headers: %w[name email], format: 'csv', rows: rows)
    allow(CampaignImports::Parser).to receive(:new).and_return(instance_double(CampaignImports::Parser, perform: parsed))
    result = described_class.new(campaign, '', filename: 'invalid.csv', import: import).perform
    expect(result.to_h.slice(:imported, :invalid, :total)).to eq(imported: 1, invalid: 1, total: 2)
    expect(campaign.email_campaign_recipients.sole.email).to eq('user+tag@example.org')
    issue = import.email_campaign_import_issues.sole
    expect([issue.reason_code, issue.row_number, issue.raw_address]).to eq(['invalid_email', 3, "bad\\xFF#{'x' * 313}"])
    expect(issue.raw_address).to be_valid_encoding
  end
end
