require 'rails_helper'
require Rails.root.join('db/migrate/20261108171000_add_conversation_message_delete_to_custom_roles.rb')

# #1893 — quem já apagava mensagens por atender conversas continua apagando depois da divisão.
RSpec.describe AddConversationMessageDeleteToCustomRoles do
  let(:account) { create(:account) }
  let!(:atende_todas) { create(:custom_role, account: account, permissions: %w[conversation_manage]) }
  let!(:atende_as_proprias) { create(:custom_role, account: account, permissions: %w[conversation_participating_manage contact_view]) }
  let!(:so_le) { create(:custom_role, account: account, permissions: %w[conversation_view]) }
  let!(:sem_conversa) { create(:custom_role, account: account, permissions: %w[crm_view]) }

  around do |example|
    verbose = ActiveRecord::Migration.verbose
    ActiveRecord::Migration.verbose = false
    example.run
  ensure
    ActiveRecord::Migration.verbose = verbose
  end

  it 'dá a chave a quem atende conversa, uma vez só' do
    2.times { described_class.new.up }

    expect(atende_todas.reload.permissions).to eq(%w[conversation_manage conversation_message_delete])
    expect(atende_as_proprias.reload.permissions).to eq(%w[conversation_participating_manage contact_view conversation_message_delete])
    expect(so_le.reload.permissions).to eq(%w[conversation_view])
    expect(sem_conversa.reload.permissions).to eq(%w[crm_view])
  end

  it 'o down tira a chave' do
    described_class.new.up
    described_class.new.down

    expect(atende_todas.reload.permissions).to eq(%w[conversation_manage])
  end
end
