require 'rails_helper'

RSpec.describe EmailSuppressionEvent do
  let(:account) { create(:account) }
  let(:registry) { EmailCampaigns::SuppressionRegistry.new(account: account, email: 'person@example.org') }

  it 'rejects updates and deletes through the model' do
    event = registry.block!(reason: 'manual', source: 'manual', event_key: 'event:1').event
    expect { event.update!(source: 'ses') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { event.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it 'rejects an audit event attributed to a different account' do
    suppression = registry.block!(reason: 'manual', source: 'manual', event_key: 'event:1').suppression
    event = described_class.new(email_suppression_state: suppression, account: create(:account),
                                event_key: 'event:2', source: 'manual', reason: 'manual', action: 'record',
                                occurred_at: Time.current, first_seen_at: Time.current, last_seen_at: Time.current)
    expect(event).not_to be_valid
    expect(event.errors[:account]).to be_present
  end
end
