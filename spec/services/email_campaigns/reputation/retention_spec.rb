require 'rails_helper'

RSpec.describe DeleteObjectJob do # rubocop:disable RSpec/SpecFilePathFormat -- reputation retention integration
  let(:account) { create(:account) }

  it 'allows actual DeleteObjectJob deletion of an account with only a healthy state' do
    state = EmailReputationState.create!(account: account, level: 'healthy')
    expect { described_class.perform_now(account) }.not_to raise_error
    expect(Account.exists?(account.id)).to be(false)
    expect(EmailReputationState.exists?(state.id)).to be(false)
  end

  it 'completes deletion including pre-purged contacts while retaining immutable audit evidence' do
    contact = create(:contact, account: account)
    state = EmailReputationState.create!(account: account, blocked: true)
    audit = EmailReputationAudit.create!(account: account, action: 'paused', snapshot: { code: 'reputation_threshold', metrics: { permanent: 5 } })
    snapshot = audit.snapshot
    expect { described_class.perform_now(account) }.not_to raise_error
    expect(Account.exists?(account.id)).to be(false)
    expect(Contact.exists?(contact.id)).to be(false)
    expect(EmailReputationState.exists?(state.id)).to be(false)
    expect(audit.reload).to have_attributes(account_id: account.id, snapshot: snapshot)
    expect { audit.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'allows deletion of an audited actor without rewriting history' do
    actor = create(:user, type: 'SuperAdmin')
    audit = EmailReputationAudit.create!(account: account, actor_id: actor.id, action: 'released', snapshot: { code: 'reviewed_release' })
    expect { described_class.perform_now(actor) }.not_to raise_error
    expect(User.exists?(actor.id)).to be(false)
    expect(audit.reload.actor_id).to eq(actor.id)
  end
end
