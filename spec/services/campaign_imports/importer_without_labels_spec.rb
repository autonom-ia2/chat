require 'rails_helper'

# #1005 N1/D3: saving an audience creates no label at all; N3: the old campaign base keeps its labels.
RSpec.describe CampaignImports::Importer, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }

  it 'validates and saves an audience without creating any label, tagging or label record' do
    labels_before = Label.count
    tags_before = ActsAsTaggableOn::Tag.count

    audience = saved_audience(account: account, user: user, content: "Nome,Celular\nAna,11987654321\nBia,21987654321\n")

    expect(audience).to be_completed
    expect(audience.batch_count).to eq(1)
    expect(audience.campaign_import_labels).to be_empty
    expect(audience.base_label).to be_nil
    expect(Label.count).to eq(labels_before)
    expect(ActsAsTaggableOn::Tag.count).to eq(tags_before)
    expect(ActsAsTaggableOn::Tagging.where(taggable_type: 'Contact', taggable_id: account.contacts.select(:id))).to be_empty
    expect(audience.campaign_import_rows.pluck(:labels_applied).uniq).to eq([[]])
    expect(audience.campaign_import_rows.status_imported.count).to eq(2)
  end

  it 'keeps creating the base and batch labels for the old campaign base flow' do
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform
    campaign_import.reload.update!(status: :queued)

    described_class.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_completed
    expect(campaign_import.campaign_import_labels.kind_base.count).to eq(1)
    expect(campaign_import.campaign_import_labels.kind_batch.count).to eq(2)
    expect(account.labels.where(title: campaign_import.base_label)).to exist
    expect(account.contacts.tagged_with(campaign_import.base_label).count).to eq(2)
  end
end
