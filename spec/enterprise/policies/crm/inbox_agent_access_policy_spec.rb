require 'rails_helper'

# Caixas no CRM (#1149): quem vê o quê nas caixas é configuração de administrador do CRM. No EE, a função com
# crm_admin também configura; agente comum e quem só gerencia funis, não.
RSpec.describe Crm::InboxAgentAccessPolicy, type: :policy do
  def ctx(user, account_user)
    { account: account, user: user, account_user: account_user }
  end

  def custom_role_user(permissions:)
    user, account_user = create_crm_agent(account: account, name: 'Custom Role User')
    role = CustomRole.create!(account: account, name: "Role #{SecureRandom.hex(4)}", permissions: permissions)
    account_user.update!(custom_role: role)
    [user, account_user]
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }

  it 'lets the administrator and a crm_admin role configure' do
    admin = account_and_admin.last
    expect(described_class.new(ctx(admin, AccountUser.find_by(user: admin)), Crm::InboxAgentAccess).update?).to be(true)

    user, account_user = custom_role_user(permissions: ['crm_admin'])
    expect(described_class.new(ctx(user, account_user), Crm::InboxAgentAccess).update?).to be(true)
  end

  it 'refuses plain agents and roles that only manage pipelines' do
    plain = create_crm_agent(account: account)
    expect(described_class.new(ctx(*plain), Crm::InboxAgentAccess).index?).to be(false)

    user, account_user = custom_role_user(permissions: %w[crm_view crm_manage_pipelines])
    expect(described_class.new(ctx(user, account_user), Crm::InboxAgentAccess).update?).to be(false)
  end
end
