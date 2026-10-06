require 'rails_helper'

RSpec.describe CampaignImports::Importer do
  it 'creates contacts, creates hidden labels, applies one batch label, and supports undo' do
    account, user = create_account_and_user
    existing_contact = account.contacts.create!(name: 'Manual', phone_number: '+5511987654321')
    existing_contact.label_list.add('manual')
    existing_contact.save!
    content = "nome,telefone\nAna,11987654321\nBia,21987654321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 2)
    CampaignImports::Validator.new(campaign_import).perform

    campaign_import.update!(status: :queued)
    described_class.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_completed
    expect(account.contacts.count).to eq(2)
    expect(account.labels.where(show_on_sidebar: false).pluck(:title)).to include(campaign_import.base_label)
    expect(existing_contact.reload.label_list).to include('manual', campaign_import.base_label)
    expect(campaign_import.campaign_import_rows.status_imported.count).to eq(2)
    expect(campaign_import.campaign_import_rows.pluck(:labels_applied).flatten.uniq).to include(campaign_import.base_label)

    described_class.new(campaign_import.reload).perform

    expect(account.contacts.count).to eq(2)
    expect(campaign_import.reload).to be_completed

    CampaignImports::UndoLabels.new(campaign_import).perform

    expect(campaign_import.reload).to be_labels_undone
    expect(existing_contact.reload.label_list).to include('manual')
    expect(existing_contact.label_list).not_to include(campaign_import.base_label)
    expect(account.contacts.count).to eq(2)

    CampaignImports::UndoLabels.new(campaign_import.reload).perform

    expect(campaign_import.reload).to be_labels_undone
    expect(account.contacts.count).to eq(2)
  end

  describe 'robustness' do
    def validated_import(content, batch_count: 1)
      account, user = create_account_and_user
      campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: batch_count)
      CampaignImports::Validator.new(campaign_import).perform
      campaign_import.update!(status: :queued)
      [account, campaign_import.reload]
    end

    it 'reuses a contact stored without the ninth digit instead of creating a duplicate' do
      account, campaign_import = validated_import("nome,telefone\nAna,45988887777\n")
      legacy = account.contacts.create!(name: 'Ana antiga', phone_number: '+554588887777')

      described_class.new(campaign_import).perform

      expect(campaign_import.reload).to be_completed
      expect(account.contacts.count).to eq(1)
      expect(campaign_import.campaign_import_rows.status_imported.pick(:contact_id)).to eq(legacy.id)
      expect(campaign_import.existing_contacts_count).to eq(1)
    end

    it 'prefers the exact number when both variants exist' do
      account, campaign_import = validated_import("nome,telefone\nAna,45988887777\n")
      account.contacts.create!(name: 'Sem nove', phone_number: '+554588887777')
      exact = account.contacts.create!(name: 'Com nove', phone_number: '+5545988887777')

      described_class.new(campaign_import).perform

      expect(campaign_import.campaign_import_rows.status_imported.pick(:contact_id)).to eq(exact.id)
    end

    it 'marks only the failing row and imports the rest, in blocks' do
      stub_const('CampaignImports::Importer::BLOCK_SIZE', 2)
      account, campaign_import = validated_import("nome,telefone\nAna,11987654321\nBia,21987654321\nCaio,31987654321\n")
      importer = described_class.new(campaign_import)
      allow(importer).to receive(:find_existing_contact).and_wrap_original do |method, phone|
        raise ActiveRecord::RecordInvalid, Contact.new if phone == '+5521987654321'

        method.call(phone)
      end

      importer.perform

      campaign_import.reload
      expect(campaign_import).to be_completed_with_failures
      expect(campaign_import.imported_contacts_count).to eq(2)
      expect(campaign_import.failed_contacts_count).to eq(1)
      expect(campaign_import.campaign_import_rows.status_import_failed.pick(:row_number)).to eq(3)
      expect(account.contacts.count).to eq(2)
    end

    it 'keeps the committed blocks and counts only the rest as failed when a block breaks' do
      stub_const('CampaignImports::Importer::BLOCK_SIZE', 2)
      _account, campaign_import = validated_import("nome,telefone\nAna,11987654321\nBia,21987654321\nCaio,31987654321\n")
      calls = 0
      allow(CampaignImports::BulkContactLabeler).to receive(:new).and_wrap_original do |method, *args|
        calls += 1
        raise ActiveRecord::StatementInvalid, 'boom' if calls == 2

        method.call(*args)
      end

      described_class.new(campaign_import).perform

      campaign_import.reload
      expect(campaign_import).to be_failed
      expect(campaign_import.imported_contacts_count).to eq(2)
      expect(campaign_import.failed_contacts_count).to eq(1)
    end
  end
end
