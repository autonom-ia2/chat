require 'rails_helper'
require Rails.root.join('db/migrate/20261108120000_add_contact_export_to_custom_roles.rb')

# #1845 — quem já exportava contatos pelo `contact_manage` continua exportando depois da divisão.
RSpec.describe AddContactExportToCustomRoles do
  let(:account) { create(:account) }
  let!(:editor) { create(:custom_role, account: account, permissions: %w[contact_manage crm_view]) }
  let!(:leitor) { create(:custom_role, account: account, permissions: %w[contact_view]) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  it 'dá contact_export a quem tem contact_manage, uma vez só' do
    2.times { described_class.new.up }

    expect(editor.reload.permissions).to eq(%w[contact_manage crm_view contact_export])
    expect(leitor.reload.permissions).to eq(%w[contact_view])
  end

  it 'o down tira a chave' do
    described_class.new.up
    described_class.new.down

    expect(editor.reload.permissions).to eq(%w[contact_manage crm_view])
  end
end
