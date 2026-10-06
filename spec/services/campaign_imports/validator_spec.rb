require 'rails_helper'

RSpec.describe CampaignImports::Validator do
  it 'keeps the first occurrence of a repeated phone and skips the repeats with a reason' do
    account, user = create_account_and_user
    content = "nome,telefone\nAna,11987654321\nBia,(11) 98765-4321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 1)

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_ready_to_confirm
    expect(account.contacts.count).to eq(0)
    expect(campaign_import.valid_rows).to eq(1)
    expect(campaign_import.invalid_rows).to eq(1)
    expect(campaign_import.campaign_import_rows.status_invalid.pick(:row_number)).to eq(3)
    expect(campaign_import.error_csv.download).to include('duplicate_phone_in_file')
    expect(campaign_import.error_csv.download).not_to include('11987654321')
  end

  it 'marks a valid file ready to confirm and stores only masked phones in rows' do
    account, user = create_account_and_user
    content = "nome,telefone\nAna,11987654321\nBia,21987654321\nCaio,31987654321\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 2)

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_ready_to_confirm
    expect(campaign_import.campaign_import_rows.status_valid.count).to eq(3)
    expect(campaign_import.campaign_import_rows.pluck(:raw_phone_masked).join).not_to include('11987654321')
    expect(campaign_import.normalized_csv.download).to include('phone_hash')
    expect(campaign_import.campaign_import_labels.kind_batch.order(:batch_index).pluck(:planned_count)).to eq([2, 1])
  end

  it 'goes on with the valid rows when some rows have problems (98 ready, 2 with problems)' do
    account, user = create_account_and_user
    valid = (1..98).map { |index| "Pessoa #{index},119#{format('%08d', 10_000_000 + index)}" }
    content = "nome,telefone\n#{valid.join("\n")}\nFixo,1133334444\nSem numero,\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 1)

    described_class.new(campaign_import).perform

    campaign_import.reload
    expect(campaign_import).to be_ready_to_confirm
    expect(campaign_import.valid_rows).to eq(98)
    expect(campaign_import.invalid_rows).to eq(2)
    expect(campaign_import.validation_summary['warnings']).to include('invalid_rows_skipped')
    expect(CSV.parse(campaign_import.normalized_csv.download, headers: true).size).to eq(98)
    errors = CSV.parse(campaign_import.error_csv.download, headers: true)
    expect(errors.size).to eq(2)
    expect(errors.pluck('errors').join).to include('invalid_brazilian_mobile_number', 'blank_phone_number')
  end

  it 'refuses the file and records nothing when no row is valid' do
    account, user = create_account_and_user
    content = "nome,telefone\nFixo,1133334444\nSem numero,\n"
    campaign_import = create_campaign_import(account: account, user: user, content: content, batch_count: 1)

    described_class.new(campaign_import).perform

    campaign_import.reload
    expect(campaign_import).to be_validation_failed
    expect(campaign_import.validation_summary['errors']).to include('no_valid_rows')
    expect(campaign_import.normalized_csv).not_to be_attached
    expect(campaign_import.campaign_import_labels.count).to eq(0)
    expect(account.contacts.count).to eq(0)
  end

  it 'logs the class of an unexpected failure without personal data' do
    account, user = create_account_and_user
    campaign_import = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")
    allow(CampaignImports::Parser).to receive(:new).and_raise(StandardError, 'broke on +5511987654321 token abcdefghijklmnopqrstuvwxyz0123456789')
    logged = []
    allow(Rails.logger).to receive(:error) { |message| logged << message }

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_validation_failed
    expect(logged.join).to include('StandardError', "import_id=#{campaign_import.id}")
    expect(logged.join).not_to include('5511987654321', 'abcdefghijklmnopqrstuvwxyz0123456789')
  end
end
