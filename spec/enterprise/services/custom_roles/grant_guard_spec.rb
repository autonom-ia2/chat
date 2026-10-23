require 'rails_helper'

# #2124: a trava de quem dá função confere as chaves como a função vai gravá-las. Uma chave de editar o CRM traz
# `crm_view`, então quem não tem `crm_view` não o entrega por tabela.
RSpec.describe CustomRoles::GrantGuard do
  let(:account) { create(:account) }
  let(:giver) { create(:user, account: account, role: :agent) }
  let(:membership) { giver.account_users.find_by!(account: account) }

  def give_giver(permissions)
    role = create(:custom_role, account: account, permissions: permissions)
    membership.update!(custom_role: role)
    role
  end

  it 'deixa quem edita cards dar uma função que edita cards' do
    give_giver(%w[crm_manage_cards custom_role_manage])

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_cards])).to be(true)
  end

  it 'não deixa quem não tem crm_view dar uma chave que o traz' do
    role = give_giver(%w[crm_view_reports custom_role_manage])
    # Função antiga, gravada antes do #2124: o callback não roda aqui de propósito.
    role.update_column(:permissions, %w[crm_manage_cards custom_role_manage]) # rubocop:disable Rails/SkipsModelValidations

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_cards])).to be(false)
  end

  it 'continua negando chave que quem dá não tem' do
    give_giver(%w[crm_view custom_role_manage])

    expect(described_class.new(actor: membership.reload).reach?(%w[crm_manage_pipelines])).to be(false)
  end
end
