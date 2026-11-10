require 'rails_helper'

# Importar contatos (#1006, #2771): the job asks again, as who uploaded the file, the Contacts screen's import
# question (ContactPolicy#import?). The upload was allowed, but the permission can be gone by the time the job runs.
RSpec.describe CampaignImports::Importer, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:mapping) { { 'name' => 0, 'phone' => 1, 'email' => 2 } }
  let(:existing) { account.contacts.create!(name: 'Ana Antiga', phone_number: '+5511987650001') }

  def contact_import
    content = "Nome,Celular,Email\nAna Nova,11987650001,\nBia,11987650002,bia@example.org\n"
    validate_contact_import(create_contact_import(account: account, user: user, content: content), mapping)
  end

  it 'imports as who uploaded and keeps the name and phone of an existing contact' do
    existing
    campaign_import = import_contacts!(contact_import)

    expect(campaign_import).to be_completed
    expect(existing.reload).to have_attributes(name: 'Ana Antiga', phone_number: '+5511987650001')
    expect(account.contacts.find_by(phone_number: '+5511987650002')).to have_attributes(name: 'Bia', email: 'bia@example.org')
  end

  it 'fails the whole import, writing nothing, when who uploaded can no longer import contacts' do
    campaign_import = contact_import
    account.account_users.find_by(user: user).update!(role: :agent)

    import_contacts!(campaign_import)

    expect(campaign_import).to be_failed
    expect(campaign_import.validation_summary['import_error']).to eq('import_not_allowed')
    expect(campaign_import.failed_contacts_count).to eq(2)
    expect(account.contacts.count).to eq(0)
  end

  it 'fails the import when who uploaded left the account' do
    campaign_import = contact_import
    account.account_users.find_by(user: user).destroy!

    expect(import_contacts!(campaign_import)).to be_failed
    expect(account.contacts.count).to eq(0)
  end
end
