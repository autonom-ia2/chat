require 'rails_helper'

RSpec.describe CampaignImport do
  it 'allows deletion before import creates contacts' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")

    CampaignImports::Validator.new(campaign_import).perform

    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import).to be_deletable_before_import
  end

  it 'blocks deletion after contacts were imported' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\nBia,21987654321\n")
    CampaignImports::Validator.new(campaign_import).perform

    campaign_import.update!(status: :queued)
    CampaignImports::Importer.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_completed
    expect(campaign_import).not_to be_deletable_before_import
  end

  # #2923: a contact import that broke midway already wrote contacts; its rows are what "Desfazer" (#2896) reads.
  describe 'a contact import' do
    def contact_import(status, account_and_user = create_account_and_user)
      account, user = account_and_user
      account.campaign_imports.create!(user: user, status: status, mode: 'single_label', options: { 'flow' => CampaignImport::CONTACTS_FLOW })
    end

    it 'can be dropped while it is a draft, or when it failed before writing any contact' do
      %i[uploaded validation_failed needs_column_choice ready_to_confirm failed cancelled expired].each do |status|
        expect(contact_import(status)).to be_deletable, status.to_s
      end
    end

    it 'cannot be dropped once a row points at a contact, even when the import ended failed' do
      account_and_user = create_account_and_user
      failed = contact_import(:failed, account_and_user)
      contact = account_and_user.first.contacts.create!(name: 'Ana Albuquerino', phone_number: '+5511987650001')
      failed.campaign_import_rows.create!(row_number: 2, status: :imported, contact_id: contact.id)

      expect(failed).not_to be_deletable
    end

    it 'cannot be dropped while it is being saved or after it was saved' do
      %i[confirmed queued importing completed completed_with_failures].each do |status|
        expect(contact_import(status)).not_to be_deletable, status.to_s
      end
    end
  end
end
