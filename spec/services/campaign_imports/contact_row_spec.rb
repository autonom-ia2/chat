require 'rails_helper'

# One import row (#2771): the core shared by Importar contatos and the automation step "para_cada".
RSpec.describe CampaignImports::ContactRow, :aggregate_failures do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin_account_user) { account.account_users.find_by(user: admin) }
  let(:linker) { CampaignImports::CompanyLinker.new(account) }

  before { account.enable_features!('companies') }

  def row_writer(account_user = admin_account_user, with_linker: true)
    described_class.new(account, account_user: account_user, linker: (linker if with_linker))
  end

  it 'creates a new contact with name, phone and e-mail' do
    result = row_writer.write(name: 'Ana Souza', phone_number: '+5511987654321', email: 'ana@example.org')

    expect(result.existing).to be(false)
    expect(result.contact).to have_attributes(name: 'Ana Souza', phone_number: '+5511987654321', email: 'ana@example.org')
  end

  it 'creates a contact with the name only when the row has no phone nor e-mail' do
    result = row_writer.write(name: 'Bruno Lima', phone_number: nil, email: nil)

    expect(result.contact).to be_persisted
    expect(result.contact).to have_attributes(name: 'Bruno Lima', phone_number: nil)
  end

  it 'finds the existing contact by the phone without the ninth digit and keeps its name and phone' do
    contact = create(:contact, account: account, name: 'Ana', phone_number: '+551187654321', email: nil)

    result = row_writer.write(name: 'Ana Souza Nova', phone_number: '+5511987654321', email: nil)

    expect(result.existing).to be(true)
    expect(result.contact.id).to eq(contact.id)
    expect(contact.reload).to have_attributes(name: 'Ana', phone_number: '+551187654321')
  end

  it 'fills only what the existing contact lacks' do
    contact = create(:contact, account: account, name: 'Ana', phone_number: nil, email: 'ana@example.org')

    row_writer.write(name: 'Outro Nome', phone_number: '+5511987654321', email: 'ana@example.org')

    expect(contact.reload).to have_attributes(name: 'Ana', phone_number: '+5511987654321', email: 'ana@example.org')
  end

  it 'links the company only to a contact without one' do
    outra = account.companies.create!(name: 'Outra Empresa')
    sem_empresa = create(:contact, account: account, phone_number: '+5511911110001', email: nil)
    de_outra = create(:contact, account: account, phone_number: '+5511911110002', email: nil, company: outra)

    primeiro = row_writer.write(name: 'A', phone_number: '+5511911110001', email: nil, company_name: 'Alfa Corretora')
    segundo = row_writer.write(name: 'B', phone_number: '+5511911110002', email: nil, company_name: 'Alfa Corretora')

    alfa = account.companies.find_by!(name: 'Alfa Corretora')
    expect(sem_empresa.reload.company_id).to eq(alfa.id)
    expect(primeiro.company.status).to eq(:created)
    expect(de_outra.reload.company_id).to eq(outra.id)
    expect(segundo.company.status).to eq(:kept_other)
  end

  it 'leaves companies alone without a linker' do
    result = row_writer(with_linker: false).write(name: 'Ana', phone_number: '+5511987654321', email: nil, company_name: 'Alfa')

    expect(result.company).to be_nil
    expect(account.companies.count).to eq(0)
  end

  it 'refuses, before writing anything, an actor without the Contacts import permission' do
    writer = row_writer(account.account_users.find_by(user: agent))

    expect(writer.allowed?).to be(false)
    expect { writer.write(name: 'Ana', phone_number: '+5511987654321', email: nil) }
      .to raise_error(described_class::NotAllowed)
    expect(account.contacts.count).to eq(0)
  end

  it 'refuses who left the account' do
    expect(row_writer(nil).allowed?).to be(false)
  end

  it 'does not ask the question in the campaign flows' do
    expect(row_writer(described_class::UNCHECKED).allowed?).to be(true)
  end
end
