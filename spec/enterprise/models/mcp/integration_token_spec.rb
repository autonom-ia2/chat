require 'rails_helper'

RSpec.describe Mcp::IntegrationToken, type: :model do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  it 'provisions a dedicated hidden user with the least Chatwoot permissions required by its scopes' do
    inbox = create(:inbox, account: account)
    token = described_class.create!(
      account: account,
      created_by: admin,
      identity_subject: 'auth-user-123',
      name: 'Autonom.ia Connect',
      scopes: described_class::DEFAULT_SCOPES
    )

    expect(token.access_token&.token).to be_present
    expect(token.account_user).to be_integration
    expect(token.account_user.user.email).to end_with('@integration.invalid')
    expect(AccessToken.where(owner: token.account_user.user)).to be_empty
    expect(InboxMember.exists?(inbox: inbox, user: token.account_user.user)).to be(true)
    expect(token.granted_scopes).to match_array(described_class::DEFAULT_SCOPES)
    expect(token.custom_role.permissions).to match_array(%w[contact_view conversation_manage inbox_view report_manage])
  end

  it 'adds access to inboxes created after provisioning without broadening the role' do
    token = described_class.create!(
      account: account,
      created_by: admin,
      identity_subject: 'auth-user-123',
      name: 'Autonom.ia Connect',
      scopes: described_class::DEFAULT_SCOPES
    )
    inbox = create(:inbox, account: account)

    expect do
      token.sync_inbox_memberships!
      token.sync_inbox_memberships!
    end.to change(InboxMember, :count).by(1)
    expect(InboxMember.exists?(inbox: inbox, user: token.account_user.user)).to be(true)
  end

  it 'rejects unsupported scopes and duplicate active integrations for the same subject and account' do
    expect do
      described_class.create!(
        account: account,
        created_by: admin,
        identity_subject: 'auth-user-123',
        name: 'Invalid',
        scopes: ['agents:admin']
      )
    end.to raise_error(ActiveRecord::RecordInvalid)

    described_class.create!(
      account: account,
      created_by: admin,
      identity_subject: 'auth-user-123',
      name: 'First',
      scopes: ['agents:conversations:read']
    )

    duplicate = described_class.new(
      account: account,
      created_by: admin,
      identity_subject: 'auth-user-123',
      name: 'Second',
      scopes: ['agents:conversations:read']
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:identity_subject]).to be_present
  end
end
