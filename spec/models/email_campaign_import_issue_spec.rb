require 'rails_helper'

RSpec.describe EmailCampaignImportIssue do
  let(:campaign) { create(:email_campaign) }
  let(:import) { campaign.email_campaign_imports.create! }

  it 'scopes visibility by account and checks import/campaign linkage' do
    issue = described_class.create!(email_campaign: campaign, email_campaign_import: import,
                                    row_number: 2, raw_address: 'bad', reason_code: 'invalid_email')
    expect(described_class.for_account(campaign.account)).to include(issue)
    expect(described_class.for_account(create(:account))).not_to include(issue)
    issue.email_campaign = create(:email_campaign)
    expect(issue).not_to be_valid
    expect(issue.errors[:email_campaign_import]).to be_present
  end

  it 'bounds raw data and makes spreadsheet export inert' do
    issue = described_class.new(email_campaign: campaign, row_number: 2, raw_address: '=test', reason_code: 'invalid_email')
    expect(issue.export_attributes['raw_address']).to eq("'=test")
    issue.raw_address = 'x' * 321
    expect(issue).not_to be_valid
  end
end
