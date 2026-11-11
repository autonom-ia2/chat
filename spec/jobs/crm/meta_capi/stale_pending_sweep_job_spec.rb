require 'rails_helper'

# #2799: a send that died midway (deploy, out of memory, database gone while releasing the row)
# leaves its row `pending`. Nobody posts it again (Meta does not dedup), and without a sweep the
# card would say "sending now" forever: the old ones become "we do not know if it arrived".
RSpec.describe Crm::MetaCapi::StalePendingSweepJob do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def event(status:, age:, owner: account, error_message: nil)
    Crm::MetaConversionEvent.create!(account: owner, event_id: SecureRandom.uuid, event_type: 'won', status: status,
                                     error_message: error_message, updated_at: age.ago)
  end

  it 'runs on the low queue' do
    expect(described_class.new.queue_name).to eq('low')
  end

  it 'is scheduled with sidekiq-cron on the low queue' do
    entry = YAML.load_file(Rails.root.join('config/schedule.yml')).values.find { |job| job['class'] == described_class.name }

    expect(entry).to include('queue' => 'low')
  end

  describe 'without an account' do
    it 'enqueues one sweep per account that has an old pending row' do
      event(status: :pending, age: 11.minutes)
      event(status: :pending, age: 2.hours)
      event(status: :pending, age: 1.minute, owner: other_account)

      expect { described_class.perform_now }.to have_enqueued_job(described_class).with(account.id).exactly(:once)
      expect(described_class).not_to have_been_enqueued.with(other_account.id)
    end

    it 'changes no row itself' do
      stale = event(status: :pending, age: 11.minutes)

      described_class.perform_now

      expect(stale.reload.status).to eq('pending')
    end
  end

  describe 'for one account' do
    it 'turns the old pending rows into an unknown outcome and leaves every other row alone' do
      stale = event(status: :pending, age: 11.minutes)
      fresh = event(status: :pending, age: 1.minute)
      accepted = event(status: :accepted, age: 1.day)
      refused = event(status: :error, age: 1.day, error_message: 'refused')
      elsewhere = event(status: :pending, age: 1.hour, owner: other_account)

      described_class.perform_now(account.id)

      expect(stale.reload).to have_attributes(status: 'error', error_message: 'unknown_outcome')
      expect(stale).to be_unknown_outcome
      expect([fresh, accepted, refused, elsewhere].map { |row| row.reload.status }).to eq(%w[pending accepted error pending])
      expect(refused.error_message).to eq('refused')
    end

    it 'handles a limited batch per run, oldest id first' do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      rows = Array.new(3) { event(status: :pending, age: 1.hour) }

      described_class.perform_now(account.id)

      expect(rows.map { |row| row.reload.status }).to eq(%w[error error pending])
    end

    it 'does nothing for an account without old pending rows' do
      fresh = event(status: :pending, age: 1.minute)

      expect { described_class.perform_now(account.id) }.not_to(change { fresh.reload.updated_at })
    end
  end
end
