require 'rails_helper'

# #1005 F1: old campaigns are linked to old imports through the hidden base label.
RSpec.describe CampaignJourney::AudienceLinkBackfill, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }

  def old_import(content = "nome,telefone\nAna,11987654321\n")
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 1)
    CampaignImports::Validator.new(campaign_import).perform
    campaign_import.reload.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import.reload).perform
    campaign_import.reload
  end

  def label_campaign(*labels, status: :completed)
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: labels.map { |label| { type: 'Label', id: label.id } },
                                 template_params: journey_template_params)
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[status]) # rubocop:disable Rails/SkipsModelValidations
    campaign
  end

  def invoke(task)
    task.reenable
    task.invoke
  end

  def base_label(campaign_import)
    account.labels.find_by!(title: campaign_import.base_label)
  end

  it 'counts in dry-run without writing, links with apply and is idempotent' do
    first = old_import
    second = old_import("nome,telefone\nBia,21987654321\n")
    linked = label_campaign(base_label(first))
    pending = label_campaign(base_label(second), status: :active)
    ambiguous = label_campaign(base_label(first), base_label(second))
    no_import = label_campaign(create(:label, account: account))
    create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params)

    dry_run = described_class.new.perform

    expect(dry_run).to eq(campaigns_with_labels: 4, linked: 1, already_linked: 0, no_import: 1, ambiguous: 1, not_completed: 1)
    expect(CampaignAudienceLink.count).to eq(0)

    expect(described_class.new(apply: true).perform).to include(linked: 1)
    expect(CampaignAudienceLink.for_campaign(linked).campaign_import).to eq(first)
    [pending, ambiguous, no_import].each { |campaign| expect(CampaignAudienceLink.for_campaign(campaign)).to be_nil }

    expect(described_class.new(apply: true).perform).to include(linked: 0, already_linked: 1)
    expect(CampaignAudienceLink.count).to eq(1)
  end

  it 'runs from the rake task, dry-run by default and writing only with APPLY=1' do
    campaign = label_campaign(base_label(old_import))
    task = Rake::Task['campaign_journey:backfill_audience_links']

    expect { invoke(task) }.to output(a_string_including('DRY-RUN')).to_stdout
    expect(CampaignAudienceLink.for_campaign(campaign)).to be_nil

    with_modified_env(APPLY: '1') do
      expect { invoke(task) }.to output(a_string_including('linked: 1')).to_stdout
    end
    expect(CampaignAudienceLink.for_campaign(campaign)).to be_present
  end
end
