require 'rails_helper'
require Rails.root.join('db/migrate/20261108163000_add_crm_delete_cards_to_custom_roles.rb')

# #1874 — quem já arquivava cards pelo `crm_manage_cards` continua arquivando depois da divisão.
RSpec.describe AddCrmDeleteCardsToCustomRoles do
  let(:account) { create(:account) }
  let!(:editor) { create(:custom_role, account: account, permissions: %w[crm_view crm_manage_cards]) }
  let!(:leitor) { create(:custom_role, account: account, permissions: %w[crm_view crm_move_cards]) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  it 'dá crm_delete_cards a quem tem crm_manage_cards, uma vez só' do
    2.times { described_class.new.up }

    expect(editor.reload.permissions).to eq(%w[crm_view crm_manage_cards crm_delete_cards])
    expect(leitor.reload.permissions).to eq(%w[crm_view crm_move_cards])
  end

  it 'o down tira a chave' do
    described_class.new.up
    described_class.new.down

    expect(editor.reload.permissions).to eq(%w[crm_view crm_manage_cards])
  end
end
