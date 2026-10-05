require 'rails_helper'

# #1005 B5: a link never crosses accounts.
RSpec.describe CampaignAudienceLink, :aggregate_failures do
  it 'requires the campaign and the audience to belong to the link account' do
    account, user = create_account_and_user
    other_account, other_user = create_account_and_user
    campaign = create(:campaign, account: account)
    other_campaign = create(:campaign, account: other_account)
    audience = create_audience_import(account: account, user: user, content: "Nome,Celular\nAna,11987654321\n")
    other_audience = create_audience_import(account: other_account, user: other_user, content: "Nome,Celular\nAna,11987654321\n")

    expect(described_class.new(account: account, campaign: campaign, campaign_import: audience)).to be_valid
    expect(described_class.new(account: account, campaign: other_campaign, campaign_import: audience)).not_to be_valid
    expect(described_class.new(account: account, campaign: campaign, campaign_import: other_audience)).not_to be_valid
    expect(described_class.new(account: account, campaign: campaign, campaign_import: nil)).to be_valid
  end
end
