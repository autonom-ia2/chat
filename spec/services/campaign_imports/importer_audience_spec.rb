require 'rails_helper'

RSpec.describe CampaignImports::Importer, :aggregate_failures do
  def validated_audience(content, mapping)
    account, user = create_account_and_user
    campaign_import = create_audience_import(account: account, user: user, content: content)
    campaign_import.update!(schema_resolution: { 'manual_mapping' => mapping, 'header_row' => 1, 'table_index' => 0 })
    CampaignImports::AudienceValidator.new(campaign_import).perform
    expect(campaign_import.reload).to be_ready_to_confirm
    campaign_import.update!(status: :queued)
    [account, campaign_import.reload]
  end

  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2, 'company' => 3 } }

  it 'creates contacts with phone and email, including email-only rows, and keeps the extra values' do
    account, campaign_import = validated_audience(
      "Nome,Celular,Email,Empresa,Plano\nAna,11987654321,ana@alfa.com.br,Alfa,Ouro\nBia,,bia@beta.com.br,Beta,Prata\n", mapping
    )

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_completed
    expect(account.contacts.order(:name).pluck(:name, :phone_number, :email)).to eq(
      [['Ana', '+5511987654321', 'ana@alfa.com.br'], ['Bia', nil, 'bia@beta.com.br']]
    )
    expect(campaign_import.campaign_import_rows.order(:row_number).pluck(:company_name, :extra_values)).to eq(
      [['Alfa', { 'Plano' => 'Ouro' }], ['Beta', { 'Plano' => 'Prata' }]]
    )
    expect(campaign_import.campaign_import_rows.status_imported.count).to eq(2)
  end

  it 'reuses a contact found by email without case difference instead of duplicating it' do
    account, campaign_import = validated_audience("Nome,Celular,Email,Empresa\nBia,,BIA@Beta.com.br,Beta\n", mapping)
    existing = account.contacts.create!(name: 'Bia antiga', email: 'bia@beta.com.br')

    described_class.new(campaign_import).perform

    expect(account.contacts.count).to eq(1)
    expect(campaign_import.reload.campaign_import_rows.pick(:contact_id, :was_existing_contact)).to eq([existing.id, true])
    expect(campaign_import.existing_contacts_count).to eq(1)
  end

  it 'prefers the phone match (with or without the 9th digit) and fills a blank email' do
    account, campaign_import = validated_audience("Nome,Celular,Email,Empresa\nAna,45988887777,ana@alfa.com.br,Alfa\n", mapping)
    legacy = account.contacts.create!(name: 'Ana', phone_number: '+554588887777')

    described_class.new(campaign_import).perform

    expect(account.contacts.count).to eq(1)
    expect(legacy.reload.email).to eq('ana@alfa.com.br')
    expect(campaign_import.reload.campaign_import_rows.pick(:contact_id)).to eq(legacy.id)
  end

  it 'leaves the email of another contact alone when the phone matches someone else' do
    account, campaign_import = validated_audience("Nome,Celular,Email,Empresa\nAna,11987654321,dono@alfa.com.br,Alfa\n", mapping)
    by_phone = account.contacts.create!(name: 'Ana', phone_number: '+5511987654321')
    owner = account.contacts.create!(name: 'Dono', email: 'dono@alfa.com.br')

    described_class.new(campaign_import).perform

    expect(campaign_import.reload).to be_completed
    expect(account.contacts.count).to eq(2)
    expect(by_phone.reload.email).to be_blank
    expect(owner.reload.email).to eq('dono@alfa.com.br')
  end
end
