require 'rails_helper'

RSpec.describe EmailSuppressionState do
  it 'does not prevent deleting an account with only a transient observation and retains its audit' do
    account = create(:account)
    registry = EmailCampaigns::SuppressionRegistry.new(account: account, email: 'recipient@example.org')
    registry.record!(reason: 'temporary_failure', source: 'ses', event_key: 'retention-transient')
    audit = EmailSuppressionEvent.find_by!(account: account)
    expect(EmailSuppression.where(account: account)).to be_empty
    account_id = account.id
    account.destroy!
    expect(described_class.where(account_id: account_id)).to be_empty
    expect(audit.reload.account_id).to eq(account_id)
    expect(audit.account).to be_nil
    expect(audit.email_suppression_state).to be_nil
    expect(audit).to be_readonly
  end
end
