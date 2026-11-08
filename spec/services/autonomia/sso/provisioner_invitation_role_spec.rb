require 'rails_helper'

# #1931: the pending invitation is checked again when accepted, against what the inviter can do now. Without a role,
# or when the inviter is no longer an administrator, it makes an agent; only a custom role of the same account, within
# the inviter's reach, is applied.
RSpec.describe Autonomia::Sso::Provisioner do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:user) { create(:user) }
  let(:provisioner) { described_class.new(context: {}) }

  before { account.enable_features!('custom_roles') }

  def accept(invitation)
    provisioner.send(:ensure_account_user, user, account, { 'invited_by_user_id' => admin.id }.merge(invitation))
  end

  it 'makes an agent when the invitation has no role' do
    expect(accept({ 'email' => user.email })).to be_agent
  end

  it 'makes an administrator when an administrator asked for it' do
    expect(accept({ 'role' => 'administrator' })).to be_administrator
  end

  it 'makes an agent when the inviter is no longer an administrator' do
    admin.account_users.find_by(account: account).update!(role: :agent)

    expect(accept({ 'role' => 'administrator' })).to be_agent
  end

  it 'applies a custom role of the same account' do
    role = create(:custom_role, account: account)

    expect(accept({ 'role' => 'agent', 'custom_role_id' => role.id }).custom_role_id).to eq(role.id)
  end

  it 'drops a custom role of another account' do
    role = create(:custom_role, account: create(:account))

    expect(accept({ 'role' => 'agent', 'custom_role_id' => role.id }).custom_role_id).to be_nil
  end

  it 'drops a custom role now above the inviter' do
    hr = create(:user, account: account, role: :agent)
    hr.account_users.find_by(account: account)
      .update!(custom_role: create(:custom_role, account: account, permissions: %w[people_manage conversation_view]))
    role = create(:custom_role, account: account, permissions: %w[crm_view])

    expect(accept({ 'invited_by_user_id' => hr.id, 'custom_role_id' => role.id }).custom_role_id).to be_nil
  end

  describe 'inboxes of the invitation' do
    it 'are applied while the inviter can manage inboxes' do
      expect(Autonomia::Sso::InvitationAccess.new(account, { 'invited_by_user_id' => admin.id })).to be_inboxes_allowed
    end

    it 'are dropped when the inviter cannot manage inboxes' do
      hr = create(:user, account: account, role: :agent)
      hr.account_users.find_by(account: account).update!(custom_role: create(:custom_role, account: account, permissions: %w[people_manage]))

      expect(Autonomia::Sso::InvitationAccess.new(account, { 'invited_by_user_id' => hr.id })).not_to be_inboxes_allowed
    end
  end
end
