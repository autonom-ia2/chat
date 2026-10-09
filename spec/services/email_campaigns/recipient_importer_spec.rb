require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientImporter do
  let(:campaign) { create(:email_campaign) }
  let(:import) { campaign.email_campaign_imports.create! }

  it 'preserves 500 row batches and reconciles rejection metadata and case-normalized duplicates' do
    EmailSuppression.create!(account: campaign.account, email: 'blocked@example.org', reason: 'manual')
    valid_rows = (1..501).map { |i| "Person #{i},person#{i}@example.org\n" }.join
    csv = "name,email\n#{valid_rows}Duplicate, PERSON1@EXAMPLE.ORG \nBlocked,blocked@example.org\nInvalid,=bad\n"
    expect(EmailCampaigns::DomainValidator).not_to receive(:new)
    expect(EmailCampaignRecipient).to receive(:insert_all!).with(an_instance_of(Array)).twice.and_call_original
    result = described_class.new(campaign, csv, filename: 'list.csv', import: import).perform
    expect(result.to_h.slice(:imported, :invalid, :duplicates, :suppressed, :total)).to eq(
      imported: 501, invalid: 1, duplicates: 1, suppressed: 1, total: 504
    )
    issue = import.email_campaign_import_issues.find_by!(reason_code: 'invalid_email')
    expect([issue.row_number, issue.raw_address, issue.export_attributes['raw_address']]).to eq([505, '=bad', "'=bad"])
    expect(campaign.email_campaign_recipients.pending.count).to eq(501)
    expect(campaign.email_campaign_recipients.find_by!(email: 'blocked@example.org')).to be_suppressed
    again = described_class.new(campaign, "name,email\nPerson,PERSON1@example.org\n", filename: 'again.csv').perform
    expect(again.duplicates).to eq(1)
  end

  it 'retains the existing global name limit without blaming a valid email address' do
    csv = "name,email\n#{'N' * 300},valid@example.org\nGood,good@example.org\n"
    result = described_class.new(campaign, csv, filename: 'names.csv', import: import).perform
    expect(result.to_h.slice(:imported, :invalid, :total)).to eq(imported: 1, invalid: 1, total: 2)
    issue = import.email_campaign_import_issues.sole
    expect([issue.reason_code, issue.row_number, issue.raw_address]).to eq(['invalid_recipient', 2, 'valid@example.org'])
  end

  it 'classifies a non-email model rejection without inventing an invalid address' do
    rejected = EmailCampaignRecipient.new(email_campaign: campaign, name: 'Rejected', email: 'valid@example.org')
    rejected.errors.add(:name, 'cannot be accepted by an integration-specific validation')
    allow(EmailCampaignRecipient).to receive(:new).and_return(rejected)
    allow(rejected).to receive(:valid?).with(:recipient_import).and_return(false)
    result = described_class.new(campaign, "name,email\nRejected,valid@example.org\n", filename: 'names.csv', import: import).perform
    expect(result.to_h.slice(:imported, :invalid, :total)).to eq(imported: 0, invalid: 1, total: 1)
    issue = import.email_campaign_import_issues.sole
    expect([issue.reason_code, issue.row_number, issue.raw_address]).to eq(['invalid_recipient', 2, 'valid@example.org'])
  end
end
