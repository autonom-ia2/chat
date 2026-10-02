require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['waha:backfill_existing_inboxes'] }

  let(:updater) { instance_double(Waha::ExistingInboxUpdater) }
  let(:result) do
    Waha::ExistingInboxUpdater::Result.new(
      total: 0, would_update: 0, updated: 0, unchanged: 0, skipped: 0, failed: 0,
      recovered: 0, recovery_failed: 0, halted: false
    )
  end

  before do
    task.reenable
    allow(Waha::ExistingInboxUpdater).to receive(:new).and_return(updater)
    allow(updater).to receive(:perform).and_return(result)
  end

  it 'keeps dry-run and unrestricted scope as defaults' do
    with_modified_env APPLY: nil, ACCOUNT_ID: nil, INBOX_ID: nil do
      expect { task.invoke }.to output(a_string_including('inbox_id=ALL')).to_stdout
    end

    expect(updater).to have_received(:perform).with(apply: false, account_id: nil, inbox_id: nil)
  end

  it 'preserves the existing account-only filter' do
    with_modified_env APPLY: nil, ACCOUNT_ID: '123', INBOX_ID: nil do
      task.invoke
    end

    expect(updater).to have_received(:perform).with(apply: false, account_id: 123, inbox_id: nil)
  end

  it 'passes a single inbox without requiring an account filter' do
    with_modified_env APPLY: nil, ACCOUNT_ID: nil, INBOX_ID: '456' do
      task.invoke
    end

    expect(updater).to have_received(:perform).with(apply: false, account_id: nil, inbox_id: 456)
  end

  [false, true].each do |apply|
    it "combines both filters with apply=#{apply}" do
      with_modified_env APPLY: apply.to_s, ACCOUNT_ID: '123', INBOX_ID: '456' do
        expect { task.invoke }.to output(a_string_including('account_id=123 inbox_id=456')).to_stdout
      end

      expect(updater).to have_received(:perform).with(apply: apply, account_id: 123, inbox_id: 456)
    end
  end

  ['', 'invalid', '456other', '0', '-1'].each do |invalid_id|
    it "rejects INBOX_ID=#{invalid_id.inspect} before constructing the updater" do
      with_modified_env APPLY: 'true', ACCOUNT_ID: nil, INBOX_ID: invalid_id do
        expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      expect(Waha::ExistingInboxUpdater).not_to have_received(:new)
      expect(updater).not_to have_received(:perform)
    end
  end

  it 'exits unsuccessfully when the selected inbox is skipped in APPLY' do
    result.skipped = 1
    result.halted = true

    with_modified_env APPLY: 'true', ACCOUNT_ID: '123', INBOX_ID: '456' do
      expect { task.invoke }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end

    expect(updater).to have_received(:perform).with(apply: true, account_id: 123, inbox_id: 456).once
  end
end
