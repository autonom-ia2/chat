require 'rails_helper'

RSpec.describe EmailCampaignImportIssue do
  let(:campaign) { create(:email_campaign) }
  let(:import) { campaign.email_campaign_imports.create!(status: :completed, result: {}) }
  let!(:issue) do
    campaign.email_campaign_import_issues.create!(email_campaign_import: import, row_number: 1,
                                                  raw_address: 'invalid.example', reason_code: 'invalid_email')
  end

  it 'cascades issues when legacy code deletes an import without knowing the new association' do
    expect do
      EmailCampaignImport.where(id: import.id).delete_all
    end.to change { described_class.where(id: issue.id).count }.from(1).to(0)
    expect(EmailCampaign.exists?(campaign.id)).to be(true)
  end

  it 'declares both new foreign keys with database-level cascade semantics' do
    rows = ActiveRecord::Base.connection.select_rows(<<~SQL.squish)
      SELECT confrelid::regclass::text, confdeltype
      FROM pg_constraint
      WHERE conrelid = 'email_campaign_import_issues'::regclass AND contype = 'f'
    SQL
    expect(rows.to_h).to include('email_campaigns' => 'c', 'email_campaign_imports' => 'c')
  end
end
