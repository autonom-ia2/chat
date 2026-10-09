require 'rails_helper'

RSpec.describe EmailCampaigns::RecipientImportJob do
  let(:campaign) { create(:email_campaign) }
  let(:import) { campaign.email_campaign_imports.create! }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    import.source_file.attach(
      io: StringIO.new("name,email\nValid,valid@example.org\nInvalid,invalid\n"), filename: 'list.csv', content_type: 'text/csv'
    )
  end

  it 'completes recipients, issues, counters and result together and does not duplicate a replay' do
    expect(EmailCampaigns::Dns::MailRouteResolver).not_to receive(:new)
    described_class.perform_now(import.id)
    expect(import.reload).to be_completed
    expect(import.result).to include('imported' => 1, 'invalid' => 1, 'total' => 2)
    expect(import.result['preflight']).to include('unchecked' => 1, 'issues' => 1)
    expect([campaign.email_campaign_recipients.count, import.email_campaign_import_issues.count]).to eq([1, 1])
    described_class.perform_now(import.id)
    expect([campaign.email_campaign_recipients.count, import.email_campaign_import_issues.count]).to eq([1, 1])
  end

  it 'rolls back inserted recipients and issues if completion fails' do
    allow(EmailCampaignImport).to receive(:find_by).with(id: import.id).and_return(import)
    allow(import).to receive(:update!).and_call_original
    allow(import).to receive(:update!).with(hash_including(status: :completed))
                                      .and_raise(StandardError, 'completion failed')
    described_class.perform_now(import.id)
    expect(import.reload).to be_failed
    expect(import.error_code).to eq('import_failed')
    expect(campaign.email_campaign_recipients.count).to eq(0)
    expect(import.email_campaign_import_issues.count).to eq(0)
  end
end
